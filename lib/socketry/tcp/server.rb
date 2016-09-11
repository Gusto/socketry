# frozen_string_literal: true

module Socketry
  # Transmission Control Protocol
  module TCP
    # Transmission Control Protocol servers: Accept connections from the network
    class Server
      include Socketry::Timeout
      alias uptime lifetime

      attr_reader :read_timeout, :write_timeout, :resolver, :socket_class

      def self.open(hostname_or_port, port = nil, **args)
        server = new(hostname_or_port, port, **args)
        result = yield server
        server.close
        result
      end

      def initialize(
        hostname_or_port,
        port = nil,
        read_timeout: Socketry::Timeout::DEFAULT_TIMEOUTS[:read],
        write_timeout: Socketry::Timeout::DEFAULT_TIMEOUTS[:write],
        timer_class: Socketry::Timeout::DEFAULT_TIMER,
        resolver: Socketry::Resolver::DEFAULT_RESOLVER,
        server_class: ::TCPServer,
        socket_class: ::TCPSocket
      )
        @read_timeout  = read_timeout
        @write_timeout = write_timeout
        @resolver      = resolver
        @socket_class  = socket_class

        if port
          @server = server_class.new(@resolver.resolve(hostname_or_port).to_s, port)
        else
          @server = server_class.new(hostname_or_port)
        end

        start_timer(timer_class: timer_class)
      end

      def accept(timeout: nil)
        set_timeout(timeout)

        begin
          # Note: `exception: false` for TCPServer#accept_nonblock is only supported in Ruby 2.3+
          ruby_socket = @server.accept_nonblock
        rescue IO::WaitReadable, Errno::EAGAIN
          # Ruby 2.2 has trouble using io/wait here
          retry if IO.select([@server], nil, nil, time_remaining(timeout))
          raise Socketry::TimeoutError, "no connection received after #{timeout} seconds"
        end

        Socketry::TCP::Socket.new(
          read_timeout:  @read_timeout,
          write_timeout: @write_timeout,
          resolver:      @resolver,
          socket_class:  @socket_class
        ).from_socket(ruby_socket)
      ensure
        clear_timeout(timeout)
      end

      def close
        return false unless @server
        @server.close rescue nil
        @server = nil
        true
      end
    end
  end
end