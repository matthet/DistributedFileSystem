require 'thread'
require "socket"
require 'time'

class ClientProxy
  def initialize(ip, port)
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
    @error2 = "\nERROR 2:File size smaller than required."
    run
  end

  def run
    loop do
      Thread.start(@proxyserver.accept) do |client|
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
      @cached = false
      if @client_msg[0..4] == "OPEN:"
        @client_fn = @client_msg[5..@client_msg.length-1]
        @is_new = client.gets.chomp
        @is_new = @is_new[7..@is_new.length-1]
        @client_msg = @client_msg[0..4] << " " << "IS_NEW:" << @is_new
        @directoryserver.puts("FILENAME:#{@client_fn}")
        listen_dserver(client)
      elsif @client_msg[0..4] == "READ:"
        @client_fn = @client_msg[5..@client_msg.length-1]
        start_pos = client.gets.chomp
        length = client.gets.chomp
        @start_n = start_pos[6..start_pos.length-1].to_i
        @len_n = length[7..length.length-1].to_i
        if File.exist?(@client_fn) #cached copy
          @accessTimeCache = File.atime(@client_fn)
          @cached = true
        end 
        @client_msg = @client_msg[0..4] << " " << @start_pos << " " << @length
        @directoryserver.puts("FILENAME:#{@client_fn}")
        listen_dserver(client)
      elsif @client_msg[0..5] == "CLOSE:"
        @client_fn = @client_msg[6..@client_msg.length-1]
        @client_msg = @client_msg[0..5]
        @directoryserver.puts("FILENAME:#{@client_fn}")
        listen_dserver(client)
      elsif @client_msg[0..5] == "WRITE:"
        @client_msg = @client_msg[0..5]
        @client_fn = @client_msg[6..@client_msg.length-1]
        @start_pos_write = client.gets.chomp
        @contents_to_write = client.gets.chomp
        @directoryserver.puts("FILENAME:#{@client_fn}")
      else
        client.puts "ERROR -1:Only OPEN, CLOSE, READ, WRITE operations allowed"
      end
    end
  end

  # Have asked the Directory Server to look for a file..
  # Create new file request: Insert into Directory and put on File Server
  # Forward on requests to applicable File Server
  def listen_dserver(client)
    msg = @directoryserver.gets.chomp
  
    if(@is_new == "1")
      if(msg[0..5] == "NOFILE")
        @lookupserver = @fileserver0 #default for all new file entries
        @server_fn = "#{@client_fn[0..@client_fn.length-5]}file.txt"
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
      if(@client_msg[0..4] == "OPEN:")
        @client_msg.insert(5,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
        listen_fserver(client)
      elsif (@client_msg[0..5] == "CLOSE:")
        @client_msg.insert(6,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
        listen_fserver(client)
      elsif (@client_msg[0..4] == "READ:")
	if @cached == true
          @lookupserver.puts("TIME:#{@server_fn}")
	  @client_msg.insert(5,"#{@server_fn}")
	  check_cache_validity(client)
	else
          @lookupserver.puts(@client_msg)
          listen_fserver(client)
	end
      else #WRITE
        @client_msg.insert(6,"#{@server_fn}")
        @lookupserver.puts(@client_msg)
        @lookupserver.puts(@start_pos_write)
        @lookupserver.puts(@contents_to_write)
      end
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
    client.puts("\n#{msg}")
  end

  def listen_fserver_read(client)
    line = @lookupserver.gets.chomp
    while line.empty? do
      line = @lookupserver.gets.chomp
    end
    msg = line
    msg = msg << "\n" << @lookupserver.gets.chomp
    msg = msg << "\n" << @lookupserver.gets.chomp
    line = @lookupserver.gets.chomp
    contents = ""
    while !line.empty? do
      contents = contents << line << "\n"
      line = @lookupserver.gets.chomp
    end
    puts contents[@start_n..(@start_n + @len_n)]
    msg = msg << "\n" << contents[@start_pos..@start_pos + @length]
    client.puts("\n#{msg}")
  end

  def check_cache_validity(client)
    msg = @lookupserver.gets.chomp
    while msg.empty? do
      msg = @lookupserver.gets.chomp
    end
    accessTimeServer = Time.parse(msg)
    compare = accessTimeServer <=> @accessTimeCache
    if (compare <= 0) #Cache copy is valid
      cache_read(client)
    else
      puts 
      @lookupserver.puts(@client_msg)
      listen_fserver_read(client)
      validate_cache(client)
    end
  end

  # Have a cached copy of the file to read
  def cache_read(client)
    file_size = File.size(@client_fn)
    start_n = @start_pos[6..@start_pos.length-1].to_i
    len_n = @length[7..@length.length-1].to_i

    if start_n >= file_size || len_n > file_size
      client.puts "#{@error2} (#{file_size})"
    else
      content = IO.binread(@client_fn, len_n, start_n)
      client.puts "\nOK:#{@client_fn}\nSTART:#{start_n}\nLENGTH:#{len_n}\n#{content}"
    end
  end

  def validate_cache(client)
    puts "sheeesh" 
  end
end

# Initialise the Proxy Server
port = 2631
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
ClientProxy.new(ip, port)
