import ApplicationServices
import Cocoa
import Darwin.C
import Foundation

// Define the server's port number
let portNumber = UInt16(57320)

// Create a socket for IPv4 and TCP
let internetLayerProtocol = AF_INET
let transportLayerType = SOCK_STREAM
let sock = socket(internetLayerProtocol, transportLayerType, 0)
guard sock >= 0 else {
  fatalError("Failed to create socket")
}

// Configure the server address
var serveraddr = sockaddr_in()
serveraddr.sin_family = sa_family_t(AF_INET)
serveraddr.sin_port = in_port_t((portNumber << 8) + (portNumber >> 8))  // Network byte order
serveraddr.sin_addr = in_addr(s_addr: in_addr_t(0))
serveraddr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)  // Padding for alignment

// Bind the socket
withUnsafePointer(to: &serveraddr) { sockaddrInPtr in
  let sockaddrPtr = UnsafeRawPointer(sockaddrInPtr).assumingMemoryBound(to: sockaddr.self)
  guard bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) >= 0 else {
    fatalError("Failed to bind socket")
  }
}

// Listen for incoming connections
guard listen(sock, 5) >= 0 else {
  fatalError("Failed to listen on socket")
}

print("Server listening on port \(portNumber)")

// Define functions to manipulate window positions
func setPosition(_ pid: pid_t, x: Int, y: Int) {
  // Placeholder for logic to set the position of a window
  print("Setting position for window with PID \(pid) to (\(x), \(y))")
}

func focusWindow(_ pid: pid_t) {
  // Placeholder for logic to focus a window
  print("Focusing window with PID \(pid)")
}

// Main server loop
// Main server loop
repeat {
  let client = accept(sock, nil, nil)
  guard client >= 0 else {
    print("Failed to accept connection")
    continue
  }

  var buffer = [UInt8](repeating: 0, count: 1024)
  let bytesRead = recv(client, &buffer, buffer.count, 0)
  guard bytesRead > 0 else {
    print("Error reading from socket")
    close(client)
    continue
  }

  // Directly create a Data object from the buffer
  let receivedData = Data(bytes: buffer, count: bytesRead)
  if let receivedString = String(data: receivedData, encoding: .utf8) {
    // Split the request into headers and body
    let parts = receivedString.components(separatedBy: "\r\n\r\n")
    guard parts.count >= 2 else {
      print("Failed to parse request")
      close(client)
      continue
    }

    let body = parts[1]

    // Debugging
    print("Received body: \(body)")

    // Now, you can safely assume body is a string containing your JSON payload
    if let jsonData = body.data(using: .utf8) {
      do {
        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
        print("Parsed JSON: \(json)")

        handleCommand(json: json as! [String: Any])
      } catch {
        print("Error parsing JSON: \(error.localizedDescription)")
      }
    }
  } else {
    print("Failed to decode buffer into string")
  }

  close(client)
} while sock > -1

close(sock)

func handleCommand(json: [String: Any]) {
  guard let command = json["command"] as? String else {
    print("Invalid command format")
    return
  }

  switch command {
  case "setPosition":
    if let pid = json["pid"] as? Int,
      let x = json["x"] as? Int,
      let y = json["y"] as? Int,
      let width = json["width"] as? Int,
      let height = json["height"] as? Int
    {
      let title = json["title"] as? String
      setPosition(pid: pid_t(pid), title: title, x: x, y: y, width: width, height: height)
    }
  case "focus":
    if let pid = json["pid"] as? Int,
      let title = json["title"] as? String
    {
      print("Focusing window with PID \(pid) and title \(title)")
      focusWindow(pid: pid_t(pid), title: title)
    }
  default:
    print("Unknown command")
  }
}

func setPosition(pid: pid_t, title: String?, x: Int, y: Int, width: Int, height: Int) {
  let position = CGPoint(x: x, y: y)
  let size = CGSize(width: width, height: height)

  let appRef = AXUIElementCreateApplication(pid)
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)

  guard result == .success, let windows = value as? [AXUIElement] else {
    print("Failed to get windows for PID: \(pid)")
    return
  }

  var didSetPosition = false
  for window in windows {
    if let targetTitle = title, !targetTitle.isEmpty {
      var titleValue: CFTypeRef?
      AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)

      if let title = titleValue as? String, title == targetTitle {
        setPositionAndSizeForWindow(window: window, position: position, size: size)
        didSetPosition = true
        break  // Stop after setting position and size for the target window
      }
    } else {
      // If no specific title is provided, apply to all windows of the application
      setPositionAndSizeForWindow(window: window, position: position, size: size)
      didSetPosition = true
    }
  }

  if !didSetPosition {
    print("No matching window found for PID: \(pid) with title: \(title ?? "nil")")
  }
}

// Helper function to set position and size for a window
func setPositionAndSizeForWindow(window: AXUIElement, position: CGPoint, size: CGSize) {
  var positionRef = position
  var sizeRef = size

  let positionValue = AXValueCreate(AXValueType.cgPoint, &positionRef)
  let sizeValue = AXValueCreate(AXValueType.cgSize, &sizeRef)

  AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue!)
  AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue!)

  print("Window position set to \(position), size set to \(size).")
}

func focusWindow(pid: pid_t, title: String? = nil) {
  let appRef = AXUIElementCreateApplication(pid)
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)

  guard result == .success, let windows = value as? [AXUIElement] else {
    print("Failed to get windows for PID: \(pid)")
    return
  }

  for window in windows {
    guard let targetTitle = title else {
      focusAndRaiseWindow(window: window)
      return  // Focus the first window if no title is specified
    }

    var titleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)

    if let title = titleValue as? String, title == targetTitle {
      focusAndRaiseWindow(window: window)
      break  // Focus and stop if the target window is found
    }
  }
}

// Helper function to focus and raise a window
func focusAndRaiseWindow(window: AXUIElement) {
  AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
  AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  print("Window focused and raised.")
}
