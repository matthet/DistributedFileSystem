require "socket"

class Client
  def initialize(proxy)
    @proxy = proxy
    @request = nil
    @response = nil
    listen
    send
    @request.join
    @response.join
  end

  def listen
    @response = Thread.new do
      loop {
        msg = @proxy.gets.chomp
        puts "#{msg}"
      }
    end
  end

  def send
    @request = Thread.new do
      loop {
        msg = $stdin.gets.chomp
        @proxy.puts(msg)
      }
    end
  end
end

port = 2631
host_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
proxy = TCPSocket.open(host_ip, port) #Open connection to Client Proxy
Client.new(proxy)
