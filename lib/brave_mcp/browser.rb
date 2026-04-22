# lib/brave_mcp/browser.rb
require "fileutils"
require "shellwords"

module BraveMcp
  class Browser
    DEFAULT_PORT = 9222
    DEFAULT_PROFILE_DIR = File.expand_path("~/.brave-mcp-profile")
    BRAVE_PATH_MAC = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
    BRAVE_PATH_WINDOWS = "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
    MAX_CONNECT_RETRIES = 10
    RETRY_DELAY = 1 # seconds
    DEFAULT_VIEWPORT_WIDTH = 1280
    DEFAULT_VIEWPORT_HEIGHT = 800
    # One file per connected MCP server; last one out closes the browser.
    CLIENTS_DIR = File.join(DEFAULT_PROFILE_DIR, "clients")

    class << self
      def instance
        return @instance if @instance && alive?
        connect_or_launch
      end

      def alive?
        return false unless @instance
        if @page
          @page.evaluate("1 + 1") == 2
        else
          # No page yet -- assume the recently-created instance is still
          # alive.  If it isn't, page creation will fail and we reconnect.
          true
        end
      rescue
        false
      end

      def connect_or_launch(port: DEFAULT_PORT)
        @console_logs = []
        @page = nil # clear stale page reference from previous connection

        # Try to connect to a debug instance that's already up.
        begin
          connect_to_existing(port)
          register_client
          return @instance
        rescue Ferrum::Error, Errno::ECONNREFUSED, Net::OpenTimeout, IO::TimeoutError
          nil
        end

        # No debug instance yet.  Register first, then elect a launcher via
        # min-PID: the live client with the lowest PID calls launch_brave.
        # If two processes race and both launch, Chromium's own profile lock
        # makes the second a no-op, so both end up connecting to the same
        # instance via connect_with_retry.
        register_client
        cleanup_stale_clients

        if designated_launcher?
          # --user-data-dir ensures this is a separate instance from any
          # personal Brave windows the user already has open.
          launch_brave(port: port)
        else
          $stderr.puts "Another BraveMCP instance is managing Brave — connecting to shared session..."
        end
        connect_with_retry(port)
      end

      def page
        instance # ensure browser is connected
        unless @page
          begin
            @page = @instance.create_page
            setup_page
          rescue Ferrum::Error
            # Browser connection may have died since startup -- reconnect
            @instance = nil
            @page = nil
            instance
            @page = @instance.create_page
            setup_page
          end
        end
        @page
      end

      def console_logs
        @console_logs ||= []
      end

      def clear_console_logs!
        @console_logs = []
      end

      # Soft disconnect used internally when we need to force a reconnect.
      # Does NOT close the browser process.
      def reset!
        @page&.close rescue nil
        @page = nil
        @instance = nil
        @console_logs = []
      end

      # Full shutdown called by at_exit.  The last connected instance closes
      # Brave; earlier exits just disconnect and let others keep using it.
      def shutdown!
        @page&.close rescue nil
        @page = nil

        unregister_client
        cleanup_stale_clients

        @instance&.command("Browser.close") rescue nil if live_clients.empty?

        @instance = nil
        @console_logs = []
      rescue StandardError
        nil
      end

      def brave_pid
        @brave_pid
      end

      private

      def designated_launcher?
        live_pids = Dir.glob(File.join(CLIENTS_DIR, "*"))
          .filter_map { |f| Integer(File.basename(f)) rescue nil }
          .select { |pid| process_alive?(pid) }
        live_pids.min == Process.pid
      end

      def register_client
        FileUtils.mkdir_p(CLIENTS_DIR)
        File.write(File.join(CLIENTS_DIR, Process.pid.to_s), "")
      end

      def unregister_client
        File.delete(File.join(CLIENTS_DIR, Process.pid.to_s)) rescue nil
      end

      def live_clients
        return [] unless Dir.exist?(CLIENTS_DIR)
        Dir.glob(File.join(CLIENTS_DIR, "*")).select do |f|
          pid = Integer(File.basename(f)) rescue nil
          pid && process_alive?(pid)
        end
      end

      def cleanup_stale_clients
        return unless Dir.exist?(CLIENTS_DIR)
        Dir.glob(File.join(CLIENTS_DIR, "*")).each do |f|
          pid = Integer(File.basename(f)) rescue nil
          File.delete(f) unless pid && process_alive?(pid)
        end
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def connect_to_existing(port)
        probe_debug_port!(port)
        @instance = Ferrum::Browser.new(url: "http://localhost:#{port}")
      end

      def probe_debug_port!(port, timeout: 3)
        require "socket"
        Socket.tcp("localhost", port, connect_timeout: timeout) { |s| s.close }
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
        raise Ferrum::Error, "No browser on localhost:#{port}: #{e.message}"
      end

      def connect_with_retry(port)
        retries = 0
        begin
          @instance = Ferrum::Browser.new(url: "http://localhost:#{port}")
        rescue Ferrum::Error, Errno::ECONNREFUSED, Net::OpenTimeout, IO::TimeoutError => e
          retries += 1
          if retries < MAX_CONNECT_RETRIES
            $stderr.puts "Waiting for Brave to start (attempt #{retries}/#{MAX_CONNECT_RETRIES})..."
            sleep RETRY_DELAY
            retry
          end
          raise ConnectionError, "Launched Brave but cannot connect on port #{port} after #{MAX_CONNECT_RETRIES} attempts. " \
            "Check that Brave is installed at: #{brave_path}"
        end
      end

      def launch_brave(port: DEFAULT_PORT)
        if wsl? && !ENV.key?("BRAVE_MCP_PROFILE")
          # Use a native Windows path so Brave doesn't get a UNC \\wsl.localhost path
          win_profile = windows_profile_dir
          linux_profile = `wslpath -u #{Shellwords.escape(win_profile)}`.strip
          FileUtils.mkdir_p(linux_profile)
          effective_profile = win_profile
          $stderr.puts "Launching Brave with profile: #{win_profile}"
        else
          profile_dir = ENV.fetch("BRAVE_MCP_PROFILE", DEFAULT_PROFILE_DIR)
          FileUtils.mkdir_p(profile_dir)
          effective_profile = wsl? ? wsl_to_windows_path(profile_dir) : profile_dir
          $stderr.puts "Launching Brave with profile: #{profile_dir}"
        end

        args = [
          brave_path,
          "--remote-debugging-port=#{port}",
          "--user-data-dir=#{effective_profile}",
          "--no-first-run",
        ]
        @brave_pid = Process.spawn(*args, [:out, :err] => File::NULL)
        Process.detach(@brave_pid)
      end

      def brave_path
        ENV.fetch("BRAVE_MCP_PATH", wsl? ? BRAVE_PATH_WINDOWS : BRAVE_PATH_MAC)
      end

      def wsl?
        @wsl ||= File.exist?("/proc/sys/fs/binfmt_misc/WSLInterop") ||
                 (File.exist?("/proc/version") && File.read("/proc/version").downcase.include?("microsoft"))
      end

      def wsl_to_windows_path(path)
        `wslpath -w #{Shellwords.escape(path)}`.strip
      end

      def windows_profile_dir
        win_home = `cmd.exe /c echo %USERPROFILE% 2>/dev/null`.strip.gsub("\r", "")
        win_home = 'C:\\Users\\Public' if win_home.empty? || win_home.include?('%')
        "#{win_home}\\.brave-mcp-profile"
      end

      def setup_page
        setup_viewport
        setup_console_listener
      end

      def setup_viewport
        # Override the viewport so the browser renders the page at a fixed
        # size independent of the actual window/tab dimensions.  This also
        # forces Chrome to composite the page even when the tab is in the
        # background, which prevents blank/white screenshots after scrolling.
        width  = ENV.fetch("BRAVE_MCP_VIEWPORT_WIDTH",  DEFAULT_VIEWPORT_WIDTH).to_i
        height = ENV.fetch("BRAVE_MCP_VIEWPORT_HEIGHT", DEFAULT_VIEWPORT_HEIGHT).to_i

        @page.command("Emulation.setDeviceMetricsOverride",
          width: width,
          height: height,
          deviceScaleFactor: 1,
          mobile: false
        )
      end

      def setup_console_listener
        @page.on(:console) do |message|
          @console_logs << {
            level: message.type,
            text: message.text,
            timestamp: Time.now.iso8601
          }
        end
      end
    end

    class ConnectionError < StandardError; end
  end
end
