require 'thread' 
require "socket"

class ClientProxy
  def initialize(size, ip, port)
    @proxyserver = TCPServer.new(ip, port)

    # Open File Server Connection(s)
    fs_port0 = 2632
    fs_ip0 = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
    @fileserver0 = TCPSocket.open(fs_ip0, fs_port0)
    
    fs_port1 = 2633
    fs_ip1 = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
    fileserver1 = TCPSocket.open(fs_ip1, fs_port1)

    @fservers = Hash.new
    @ips = Hash.new
    @tcps = Hash.new

    @fservers[:ips] = @ips
    @fservers[:tcps] = @tcps
    @fservers[:ips][fs_port0] = fs_ip0
    @fservers[:ips][fs_port1] = fs_ip1
    @fservers[:tcps][fs_port0] = @fileserver0
    @fservers[:tcps][fs_port1] = fileserver1
    @lookupserver

    # Open Directory Server Connection
    @ds_port = 2634
    @ds_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
    @directoryserver = TCPSocket.open(@ds_ip, @ds_port)
    @error0 = "\nERROR 0:File already exists.\n\n"

    @size = size
    @jobs = Queue.new

    # Threadpooled Multithreaded Server to handle Client requests
    # Each thread store its’ index in a thread-local variable
    @pool = Array.new(@size) do |i|
      Thread.new do
        Thread.current[:id] = i

        # Shutdown of threads
        catch(:exit) do
          loop do
            job, args = @jobs.pop
            job.call(*args)
          end
        end
      end
    end
    run
  end

  def schedule(*args, &block)
      @jobs << [block, args]
  end

  def run
    loop do
      schedule(@proxyserver.accept) do |client|
        client.puts "Ready, Ready, Readddyyyy...\n"
        listen_client(client)
      end
    end
  end

  def listen_client(client)
    loop do
      client.puts "\nYour request: \n"
      @client_msg = client.gets.chomp
      @client_fn = ""
      @server_fn = ""
      if @client_msg[0..4] == "OPEN:"
        @client_fn = @client_msg[5..@client_msg.length-1]
        @is_new = client.gets.chomp
        @is_new = @is_new[7..@is_new.length-1]
        @client_msg = @client_msg[0..4] << " " << "IS_NEW:" << @is_new 
        @directoryserver.puts("FILENAME:#{@client_fn}")
      elsif @client_msg[0..4] == "READ:"
        @client_fn = @client_msg[5..@client_msg.length-1]
        @client_msg = @client_msg[0..4] << " " << client.gets.chomp << " " << client.gets.chomp
        @directoryserver.puts("FILENAME:#{@client_fn}")
      elsif @client_msg[0..5] == "CLOSE:"
        @client_fn = @client_msg[6..@client_msg.length-1]
        @client_msg = @client_msg[0..5]
        @directoryserver.puts("FILENAME:#{@client_fn}")
      elsif @client_msg[0..5] == "WRITE:"
        @client_msg = @client_msg[0..5]
        @client_fn = @client_msg[6..@client_msg.length-1]
        @start_pos_write = client.gets.chomp
        @contents_to_write = client.gets.chomp
        @directoryserver.puts("FILENAME:#{@client_fn}")
      else
        client.puts "ERROR -1:Only OPEN, CLOSE, READ, WRITE operations allowed"
      end
    listen_dserver(client)
    end
  end

  def listen_dserver(client)
    msg = @directoryserver.gets.chomp

    if(@is_new == "1")
      if(msg[0..5] == "NOFILE")
        @lookupserver = @fileserver0 #default for all new file entries
        @server_fn = "#{@client_fn}file.txt"
        @client_msg.insert(5,@server_fn)
        @directoryserver.puts("INSERT:#{@client_fn} SERVER_FN:#{@server_fn}")
        @lookupserver.puts(@client_msg)
        listen_fserver(client)
      # Client trying to create a new file with the same name as another
      # Implemented in this way for ease
      else
        client.puts @error0
      end
    else 
      msg = msg.split(" ")
      ip = msg[0][7..msg[0].length-1]
      port = msg[1][5..msg[1].length-1]
      @server_fn = msg[2][9..msg[2].length-1]
      @fservers[:ips].each do |other_port, other_ip|
        if(port == other_port.to_s && ip == other_ip.to_s)
          @lookupserver = @fservers[:tcps][other_port]
        end
      end
      if(@client_msg[0..4] == "OPEN:" || @client_msg[0..4] == "READ:")
        @client_msg.insert(5,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
      elsif @client_msg[0..5] == "CLOSE:"
        @client_msg.insert(6,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
      else #WRITE
        @client_msg.insert(6,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
        @lookupserver.puts(@start_pos_write)
        @lookupserver.puts(@contents_to_write)
      end
      listen_fserver(client)
    end
  end

  def listen_fserver(client)
    line = @lookupserver.gets.chomp
    while line.empty? do
      line = @lookupserver.gets.chomp
    end
    msg = line
    line = @lookupserver.gets.chomp
    while !line.empty? do
      msg = msg << "\n" << line
      line = @lookupserver.gets.chomp
    end

    msg = msg.sub(@server_fn, @client_fn)
    client.puts("\n#{msg}\n")
  end
end

# Initialise the Proxy Server
port = 2631
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
ClientProxy.new(10, ip, port)
