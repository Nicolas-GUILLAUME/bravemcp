# lib/brave_mcp/server.rb
module BraveMcp
  class Server
    def self.run
      server = FastMcp::Server.new(name: "brave-mcp", version: VERSION)

      register_tools(server)

      # Connect to existing Brave or auto-launch with dedicated profile
      begin
        Browser.instance
        if Browser.brave_pid
          $stderr.puts "BraveMCP launched and connected to Brave browser (PID: #{Browser.brave_pid})"
        else
          $stderr.puts "BraveMCP connected to existing Brave browser"
        end
      rescue Browser::ConnectionError => e
        $stderr.puts "Warning: #{e.message}"
        $stderr.puts "Tools will attempt to connect on first use."
      end

      at_exit do
        Browser.shutdown!
      end

      server.start
    end

    def self.register_tools(server)
      Dir[File.join(__dir__, "tools", "*.rb")].sort.each { |f| require f }

      Tools.constants.each do |const|
        tool_class = Tools.const_get(const)
        server.register_tool(tool_class) if tool_class < FastMcp::Tool
      end
    end
  end
end
