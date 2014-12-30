require 'thread'
require "socket"

class FileServer1
  def initialize(size, ip, port)
    @fileserver = TCPServer.new(ip, port)

    @error2 = "\nERROR 2:File size smaller than required."

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

  # Tell the pool that work is to be done: a client is trying to connect
  def schedule(*args, &block)
    @jobs << [block, args]
  end

  # Entry Point
  # Schedule a client request
    def run
    loop do
      schedule(@fileserver.accept) do |client|
        loop do
          request = client.gets.chomp
          if request[0..4] == "OPEN:"
            open_request(request, client)
          elsif request[0..5] == "CLOSE:"
            close_request(request[6..request.length-1].to_s, client)
          elsif request[0..4] == "READ:"
            read_request(request, client)
          elsif request[0..5] == "WRITE:"
            write_request(request, client)
          end
        end
      end
    end
    @fileserver.close
    at_exit { @pool.shutdown }
    end

  # Client has requested to open a file
  def open_request(request, client)
    split_request = request.split(" ")
    puts split_request
    filename = split_request[0][5..split_request[0].length]
    is_new = split_request[1][7..split_request[1].length]
    if is_new == "1" #create new file request
      File.open(filename, "w"){ |somefile| somefile.puts "Hello new file!"}
      puts "\nOK:#{filename}\n\n"
      client.puts "\nOK:#{filename}\n\n"
    else
      File.open(filename)
      client.puts "\nOK:#{filename}\n\n"
    end
  end

  # Client has requested to close a file
  # Null operation.. can't check if file is closed without opening first.
  def close_request(filename, client)
    if File.exist?(filename)
      client.puts "\nOK:#{filename}\n\n"
    else
      client.puts @error1
    end
  end

  # Client has requested to read a file
  def read_request(request, client)
    split_request = request.split(" ")
    filename = split_request[0][5..split_request[0].length]
    start_n = split_request[1][6..split_request[1].length].to_i
    len_n = split_request[2][7..split_request[2].length].to_i
    if File.exist?(filename)
      file_size = File.size(filename)
      if start_n >= file_size || len_n > file_size
        client.puts "#{@error2} (#{file_size})\n\n"
      else
        content = IO.binread(filename,len_n,start_n)
        client.puts "\nOK:#{filename}\nSTART:#{start_n}\nLENGTH:#{len_n}\n#{content}\n\n"
      end
    else client.puts @error1
    end
  end

  # Client has requested to write to a file
  def write_request(request, client)
    filename = request[6..request.length]
    request = client.gets.chomp
    start_n = request[6..request.length].to_i
    contents = client.gets
    if File.exist?(filename)
      IO.binwrite(filename, contents, start_n)
      client.puts "\nOK:#{filename}\nSTART:#{start_n}\n\n"
    else client.puts @error1
    end
  end

  # Shutdown, wait for all threads to exit.
  def shutdown
    @size.times do
      schedule { throw :exit }
    end
    @pool.map(&:join)
  end
end

# Initialise the File Server
fs_port = 2633
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
FileServer1.new(10, ip, fs_port)
