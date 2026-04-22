# lib/brave_mcp/tools/devtools.rb
module BraveMcp
  module Tools
    class GetConsoleLogs < FastMcp::Tool
      description "Get browser console messages"

      arguments do
        optional(:level).filled(:string).description("Filter by level: all, log, warn, error, info, debug")
        optional(:clear).filled(:bool).description("Clear logs after retrieving")
      end

      def call(level: "all", clear: false)
        logs = BraveMcp::Browser.console_logs.dup

        unless level == "all"
          logs = logs.select { |log| log[:level].to_s == level }
        end

        BraveMcp::Browser.clear_console_logs! if clear

        { logs: logs, count: logs.size }
      end
    end

    class ClearConsole < FastMcp::Tool
      description "Clear captured console logs"

      arguments {}

      def call
        BraveMcp::Browser.clear_console_logs!
        { success: true }
      end
    end

    class GetNetworkRequests < FastMcp::Tool
      description "Get captured network requests"

      arguments do
        optional(:filter).filled(:string).description("Filter by resource type: xhr, fetch, document, script, stylesheet, image, font, other")
      end

      def call(filter: nil)
        traffic = BraveMcp::Browser.page.network.traffic

        requests = traffic.map do |exchange|
          req = exchange.request
          resp = exchange.response

          {
            id: exchange.id,
            url: req&.url,
            method: req&.method,
            type: req&.type,
            status: resp&.status,
            size: resp&.body_size
          }
        end

        if filter
          requests = requests.select { |r| r[:type]&.downcase == filter.downcase }
        end

        { requests: requests, count: requests.size }
      end
    end

    class GetRequestDetails < FastMcp::Tool
      description "Get full details of a specific network request"

      arguments do
        required(:request_id).filled(:string).description("Request ID from get_network_requests")
      end

      def call(request_id:)
        traffic = BraveMcp::Browser.page.network.traffic
        exchange = traffic.find { |ex| ex.id == request_id }

        return { error: "Request not found: #{request_id}" } unless exchange

        req = exchange.request
        resp = exchange.response

        {
          request: {
            url: req&.url,
            method: req&.method,
            headers: req&.headers
          },
          response: {
            status: resp&.status,
            headers: resp&.headers,
            body_preview: resp&.body&.to_s&.slice(0, 1000)
          }
        }
      end
    end

    class ClearNetwork < FastMcp::Tool
      description "Clear captured network logs"

      arguments {}

      def call
        BraveMcp::Browser.page.network.clear(:traffic)
        { success: true }
      end
    end

    class GetPerformanceMetrics < FastMcp::Tool
      description "Get page performance metrics"

      arguments {}

      def call
        page = BraveMcp::Browser.page

        metrics = page.evaluate <<~JS
          (() => {
            const perf = performance;
            const timing = perf.timing;
            const navigation = perf.getEntriesByType('navigation')[0] || {};

            return {
              loadTime: timing.loadEventEnd - timing.navigationStart,
              domContentLoaded: timing.domContentLoadedEventEnd - timing.navigationStart,
              firstPaint: perf.getEntriesByName('first-paint')[0]?.startTime || null,
              firstContentfulPaint: perf.getEntriesByName('first-contentful-paint')[0]?.startTime || null,
              domInteractive: timing.domInteractive - timing.navigationStart,
              resourceCount: perf.getEntriesByType('resource').length,
              memory: perf.memory ? {
                usedJSHeapSize: perf.memory.usedJSHeapSize,
                totalJSHeapSize: perf.memory.totalJSHeapSize
              } : null
            };
          })()
        JS

        { metrics: metrics }
      end
    end

    class GetCookies < FastMcp::Tool
      description "Get cookies for the current page"

      arguments do
        optional(:name).filled(:string).description("Filter by cookie name")
      end

      def call(name: nil)
        cookies = BraveMcp::Browser.page.cookies.all

        if name
          cookie = cookies[name]
          return { cookie: cookie&.to_h } if cookie
          return { error: "Cookie not found: #{name}" }
        end

        { cookies: cookies.transform_values(&:to_h) }
      end
    end

    class SetCookie < FastMcp::Tool
      description "Set a cookie"

      arguments do
        required(:name).filled(:string).description("Cookie name")
        required(:value).filled(:string).description("Cookie value")
        optional(:domain).filled(:string).description("Cookie domain")
        optional(:path).filled(:string).description("Cookie path")
        optional(:expires).filled(:integer).description("Expiration timestamp")
        optional(:http_only).filled(:bool).description("HTTP only flag")
        optional(:secure).filled(:bool).description("Secure flag")
      end

      def call(name:, value:, domain: nil, path: nil, expires: nil, http_only: nil, secure: nil)
        options = { name: name, value: value }
        options[:domain] = domain if domain
        options[:path] = path if path
        options[:expires] = expires if expires
        options[:httpOnly] = http_only unless http_only.nil?
        options[:secure] = secure unless secure.nil?

        BraveMcp::Browser.page.cookies.set(**options)
        { success: true }
      end
    end

    class DeleteCookies < FastMcp::Tool
      description "Delete cookies"

      arguments do
        optional(:name).filled(:string).description("Cookie name to delete (all if omitted)")
      end

      def call(name: nil)
        if name
          url = BraveMcp::Browser.page.url
          BraveMcp::Browser.page.cookies.remove(name: name, url: url)
        else
          BraveMcp::Browser.page.cookies.clear
        end
        { success: true }
      end
    end

    class GetLocalStorage < FastMcp::Tool
      description "Get localStorage data"

      arguments do
        optional(:key).filled(:string).description("Specific key to get (all if omitted)")
      end

      def call(key: nil)
        page = BraveMcp::Browser.page

        if key
          value = page.evaluate("localStorage.getItem(#{key.to_json})")
          { key: key, value: value }
        else
          data = page.evaluate("Object.fromEntries(Object.entries(localStorage))")
          { data: data }
        end
      end
    end

    class SetLocalStorage < FastMcp::Tool
      description "Set a localStorage value"

      arguments do
        required(:key).filled(:string).description("Storage key")
        required(:value).filled(:string).description("Storage value")
      end

      def call(key:, value:)
        page = BraveMcp::Browser.page
        page.execute("localStorage.setItem(#{key.to_json}, #{value.to_json})")
        { success: true }
      end
    end
  end
end
