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
    #fileserver1 = TCPSocket.open(fs_ip1, fs_port1)

    @fservers = Hash.new
    @ips = Hash.new
    @tcps = Hash.new

    @fservers[:ips] = @ips
    @fservers[:tcps] = @tcps
    @fservers[:ips][fs_port0] = fs_ip0
    @fservers[:ips][fs_port1] = fs_ip1
    @fservers[:tcps][fs_port0] = @fileserver0
    #@fservers[:tcps][fs_port1] = fileserver1
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
      elsif @client_msg[0..4] == "READ:"
        @client_fn = @client_msg[5..@client_msg.length-1]
        start_pos = client.gets.chomp
        len = client.gets.chomp
        @start_n = start_pos[6..start_pos.length-1].to_i
        @len_n = len[7..len.length-1].to_i
        if File.exist?(@client_fn) #cached copy
          @accessTimeCache = File.atime(@client_fn)
          @cached = true
        end 
        @client_msg = @client_msg[0..4] << " " << start_pos << " " << len
        @directoryserver.puts("FILENAME:#{@client_fn}")
      elsif @client_msg[0..5] == "CLOSE:"
        @client_fn = @client_msg[6..@client_msg.length-1]
        @client_msg = @client_msg[0..5]
        @directoryserver.puts("FILENAME:#{@client_fn}")
      elsif @client_msg[0..5] == "WRITE:"
        @client_fn = @client_msg[6..@client_msg.length-1]
        @start_n = client.gets.chomp
        @contents = client.gets.chomp
        if File.exist?(@client_fn) #cached copy
          n = @start_n[6..@start_n.length-1].to_i
	  IO.binwrite(@client_fn, @contents, n)          
        end #write - through
        @directoryserver.puts("FILENAME:#{@client_fn}")
      else
        client.puts "ERROR -1:Only OPEN, CLOSE, READ, WRITE operations allowed"
      end
      listen_dserver(client)
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
        @lookupserver.puts("WRITE:#{@server_fn}")
        @lookupserver.puts(@start_n)
        @lookupserver.puts(@contents)
	listen_fserver(client)
      end
    end
  end

  # Listen for responses from file server.
  # Could be resonses for 'Open', 'Close', 'Time' of last file access for caching
  def listen_fserver(client)
    line = @lookupserver.gets.chomp
    while line.empty? do
      line = @lookupserver.gets.chomp
    end
    msg = line
    puts msg
    line = @lookupserver.gets.chomp
    while !line.empty? do
      msg = msg << "\n" << line
      line = @lookupserver.gets.chomp
    end

    msg = msg.sub(@server_fn, @client_fn)
    client.puts("\n#{msg}")
  end

  # Reading, Caching ----------------------------------------------------------------------

  # Check for stale data in cache.
  # Compare file access time of file on server and cached copy.
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
      puts @client_msg
      @lookupserver.puts(@client_msg)
      listen_fserver_read(client)
    end
  end

  # File in cache, and is valid
  def cache_read(client)
    file_size = File.size(@client_fn)

    if @start_n >= file_size || @len_n > file_size
      client.puts "#{@error2} (#{file_size})"
    else
      content = IO.binread(@client_fn, @len_n, @start_n)
      client.puts "\nOK:#{@client_fn}\nSTART:#{@start_n}\nLENGTH:#{@len_n}\n#{content}"
    end
  end

  # Reading files from file servers
  # Display only part of file specifically requested for by Client
  # Cache file.
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
    puts msg
    while !line.empty? do
      contents = contents << line << "\n"
      line = @lookupserver.gets.chomp
    end
    msg = msg << "\n" << contents[@start_n..@start_n + @len_n]
    client.puts("\n#{msg}")
    validate_cache(contents, client)
  end

  # Save up to date file in cache
  def validate_cache(contents, client)
    File.delete(@client_fn)
    File.open(@client_fn, "w")
    IO.binwrite(@client_fn, contents, 0)
  end
end

# -----------------------------------------------------------------------------------------

# Initialise the Proxy Server
port = 2631
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
ClientProxy.new(ip, port)
