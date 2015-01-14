require "socket"

class DirectoryServer
  def initialize(size, ip, port)
    @d_server = TCPServer.open(ip, port)
    @directories = Hash.new
    @ser_fns = Hash.new
    @ser_ips = Hash.new
    @ser_ports = Hash.new
    @directories[:ser_fns] = @ser_fns
    @directories[:ser_ports] = @ser_ports
    @directories[:ser_ips] = @ser_ips

    @fs_ip0 = @fs_ip1 = "134.226.32.10" 
    @fs_port0 = "2632"
    @fs_port1 = "2633"

    # 2 existing files (1 on each server) 
    # Put these in Directory
    @directories[:ser_fns]["hello.txt"] = "hellofile.txt"
    @directories[:ser_fns]["xmas.txt"] = "christmasfile.txt"
    @directories[:ser_ports]["hellofile.txt"] = @fs_port0
    @directories[:ser_ports]["christmasfile.txt"] = @fs_port1
    @directories[:ser_ips][@fs_port0] = @fs_ip0
    @directories[:ser_ips][@fs_port1] = @fs_ip1
    run
  end

  def run
    loop do
      Thread.start(@d_server.accept) do |client|
        loop do
          msg = client.gets.chomp
          if msg[0..6] == "INSERT:"
            insert_into_directory(msg)
          else
            filename = msg[9..msg.length-1].to_s
            look_up_file(filename, client)
          end
        end
      end
    end
  end

  def insert_into_directory(msg)
    msg = msg.split(" ")
    client_fn = msg[0][7..msg[0].length-1]
    server_fn = msg[1][10..msg[1].length-1]
    @directories[:ser_fns][client_fn] = server_fn
    @directories[:ser_ports][server_fn] = @fs_port0
  end

  def look_up_file(filename, client)
    puts filename
    $server_fn
    $server_ip
    $server_port
    @directories[:ser_fns].each do |other_name, fs_filename|
      if(filename == other_name)
        $server_fn = fs_filename
      end
    end
    if $server_fn.nil?
      client.puts "NOFILE"
    else
      @directories[:ser_ports].each do |other_name, fs_port|
        if($server_fn == other_name)
          $server_port = fs_port
        end
      end
      @directories[:ser_ips].each do |other_server, fs_ip|
        if($server_port == other_server)
          $server_ip = fs_ip
        end
      end
      client.puts "SERVER:#{$server_ip} PORT:#{$server_port} FILENAME:#{$server_fn}"
    end
  end
end

# Initialise the Directory Server
ds_port = 2634
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
DirectoryServer.new(10, ip, ds_port)
