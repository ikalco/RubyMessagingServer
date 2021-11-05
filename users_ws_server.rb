require 'socket' # Provides TCPServer and TCPSocket classes
require 'digest/sha1'

def sendMessage (socket, msg, id = -1)
  if (id == -1) then id = "?" end
  STDERR.puts "Sending message to #{id}: #{ msg.inspect }"

  output = [0b10000001, msg.size, msg]

  socket.write output.pack("CCA#{ msg.size }")
end

def recvMessage (socket, id = -1)
  if (id == -1) then id = "?" end
  first_byte = socket.getbyte
  fin = first_byte & 0b10000000
  opcode = first_byte & 0b00001111

  #puts "Opcode: #{ opcode }"

  raise "We don't support continuations" unless fin
  if opcode == 1
    #raise "We only support opcode 1 and 8" unless opcode == 1 || opcode == 8

    second_byte = socket.getbyte
    is_masked = second_byte & 0b10000000
    payload_size = second_byte & 0b01111111

    #puts payload_size

    raise "All incoming frames should be masked according to the websocket spec" unless is_masked
    raise "We only support payloads < 126 bytes in length" unless payload_size < 126

    #STDERR.puts "Payload size: #{ payload_size } bytes"

    mask = 4.times.map { socket.getbyte }
    #STDERR.puts "Got mask: #{ mask.inspect }"

    data = payload_size.times.map { socket.getbyte }
    #STDERR.puts "Got masked data: #{ data.inspect }"

    unmasked_data = data.each_with_index.map { |byte, i| byte ^ mask[i % 4] }
    #STDERR.puts "Unmasked the data: #{ unmasked_data.inspect }"

    plainMsg = unmasked_data.pack('C*').force_encoding('utf-8')

    #STDERR.puts "Converted to a string: #{ plainMsg.inspect }"

    STDERR.puts "Recieved message from #{id}: #{plainMsg.inspect}"

    return plainMsg
  elsif opcode == 8
    return "Close"
  else
    raise "We only support opcode 1 and 8"
  end
end

def websocketHandshake (socket)
  # Read the HTTP request. We know it's finished when we see a line with nothing but \r\n
  http_request = ""
  while (line = socket.gets) && (line != "\r\n")
    http_request += line
  end


  # Grab the security key from the headers. If one isn't present, close the connection.
  if matches = http_request.match(/^Sec-WebSocket-Key: (\S+)/)
    websocket_key = matches[1]
    STDERR.puts "Websocket handshake detected with key: #{ websocket_key }"
  else
    STDERR.puts "Aborting non-websocket connection"
    socket.close
    return
  end


  response_key = Digest::SHA1.base64digest([websocket_key, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"].join)
  #STDERR.puts "Responding to handshake with key: #{ response_key }"

  socket.write <<-eos
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: #{ response_key }

  eos

  STDERR.puts "Handshake completed."
end

def sendFile (socket, filePath)
    if (filePath == "") then filePath = "index.html" end
    fileTypeBefore = filePath.split('.')[-1]
    if (fileTypeBefore == 'html')
        fileType = 'html'
    elsif (fileTypeBefore == 'css')
        fileType = 'css'
    elsif (fileTypeBefore == 'js')
        fileType = 'javascript'
    elsif (fileTypeBefore == 'mjs')
        #fileType = 'javascript'
    elsif (fileTypeBefore == "txt")
        #fileType = 'plain'
        return
    else
        #fileType = filePath.split('.')[-1];
        return
    end

    data = "HTTP/1.1 200 OK\r\n"
    data += "Content-Type: text/" + fileType + "; charset=utf-8\r\n"
    data += "\r\n"

    file = File.open(filePath)
    fileData = file.read
    file.close

    data += fileData + "\r\n\r\n"
    socket.write data
end

def saveMessage (msg)
  if $messages.length >= 100 then $messages.shift end
  $messages.push msg
end

class Client
    def initialize(socket, id, name)
        @socket = socket
        @name = name
        @id = id
    end

    attr_reader :socket, :name, :id
    attr_writer :socket, :name, :id
end

httpServer = TCPServer.new 5500

puts "Access http://localhost:5500"

webSocketServer = TCPServer.new 2345

$clients = Array.new()
$usernames = Array.new()
$messages = Array.new()

loop do

  # serving html
  Thread.new {
    loop do

      httpClient = httpServer.accept
      # Read the HTTP request. We know it's finished when we see a line with nothing but \r\n
      httpRequest = ""
      while (line = httpClient.gets) && (line != "\r\n")
          httpRequest += line
      end

      pieces = httpRequest.split("\n")
      if pieces.length > 0
          STDERR.puts pieces[0]
          if pieces[0].include? "GET"
              if pieces[0].include? " /"
                  filePath = pieces[0].split(' ')[1][1..-1]
                  sendFile httpClient, filePath
              end
          end
      end
      httpClient.close
    end
  }

  # websocket loop  
  Thread.start(webSocketServer.accept) do |socket|

    websocketHandshake socket 
      
    id = -1

    while true do
        # when someone joins we wait until they send us a username
        # when they do then we send them an id and add them to the clients list

        userMsg = recvMessage socket
        if userMsg[0] != "[" then next end
        if userMsg[-1] != "]" then next end        
        if !userMsg.include? "," then next end

        # gets the value [HERE,text]              
        header = userMsg.split(/,/)[0][1..-1]
        # gets the value [msg,HERE]        
        data = userMsg.split(/,/)[1][0..-2]

        if header == "uname"
            if $usernames.include? data
                # if the username is already in use
                sendMessage socket, "[ntfcn,invalidUser]"
                next
            else
                # if the username is brand new
                id = $clients.length
                $clients[id] = Client.new(socket, id, data)
                $usernames[id] = data
                #STDERR.puts usernames.inspect
                STDERR.puts "Connected to Client #{ id }: #{ $usernames[id] }"
                sendMessage socket, "[ntfcn,validUser]", id
                sendMessage socket, "[ID,#{ id }]", id
                break
            end
            # search through usernames list to see if the user is already made
            # if it is then we send back a notification saying that the user is already made
            # if it isn't then we send an id (the length of the usernames list)
        else
            next
        end
    end

    if id == -1 
        socket.close 
    end

    client = $clients[id]

    joinMessage = "[msg,[SERVER]: #{client.name} joined the room!]"    

    # load in all messages to this client
    for msg in $messages
      sendMessage client.socket, msg, client.id
    end

    #messages.push joinMessage
    saveMessage joinMessage

    # send joined message of this client to all clients
    for selectClient in $clients
      sendMessage selectClient.socket, joinMessage, selectClient.id
    end

    prevMsg = ''
    fouls = 0

    while (true)
      msg = recvMessage client.socket, client.id
      if fouls >= 10 then msg = "Close" end
      if msg == "Close"
        leaveMessage = "[msg,[SERVER]: #{client.name} left the room!]"
        # send leave message of this client to all clients
        for selectClient in $clients
          sendMessage selectClient.socket, leaveMessage, selectClient.id
        end

        #messages.push leaveMessage
        saveMessage leaveMessage
        
        STDERR.puts "Disconnected from client #{client.id}: #{$usernames[id]}"

        $clients.delete_at(id)
        $usernames.delete_at(id)

        # need to resend all ids since an id was destroyed
        
        for selectClient in 0...$clients.length
            $clients[selectClient].id = selectClient;
            sendMessage $clients[selectClient].socket, "[ID,#{ selectClient }]", $clients[selectClient].id
        end
        break
      else
        if msg[0] != "[" then next end
        if msg[-1] != "]" then next end        
        if !msg.include? "," then next end
        if prevMsg == msg 
          sendMessage client.socket, "[ntfcn,sameMsg]", client.id
          fouls += 1
          next
        end

        prevMsg = msg

        # gets the value [HERE,text]              
        header = msg.split(/,/)[0][1..-1]
        # gets the value [msg,HERE]        
        data = msg.split(/,/)[1][0..-2]

        if header == "msg"
          for selectClient in $clients
            sendMessage selectClient.socket, "[msg,#{client.name}: #{data}]", client.id
          end
          saveMessage "[msg,#{client.name}: #{data}]"
          #messages.push "[msg,#{client.name}: #{data}]"
        elsif header == "debug"
          if data == "printClients"
            STDERR.puts $clients.inspect
          elsif data == "printMessages"
            STDERR.puts $messages.inspect
          elsif data == "printUsers"
            STDERR.puts $usernames.inspect
          end
        end        
      end
    end

    client.socket.close()
  end
end

httpServer.close
webSocketServer.close();