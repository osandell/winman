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

  let receivedData = Data(bytes: buffer, count: bytesRead)
  if let receivedString = String(data: receivedData, encoding: .utf8),
    let separatorRange = receivedString.range(of: "\r\n\r\n"),
    let jsonData = String(receivedString[separatorRange.upperBound...]).data(using: .utf8)
  {
    do {
      let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
      let statusCode = handleCommand(json: json as! [String: Any])
      let response =
        "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))\r\nContent-Length: 0\r\n\r\n"
      send(client, response, response.lengthOfBytes(using: .utf8), 0)
    } catch {
      print("Error parsing JSON: \(error.localizedDescription)")
      let errorResponse = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n"
      send(client, errorResponse, errorResponse.lengthOfBytes(using: .utf8), 0)
    }
  } else {
    print("Failed to decode buffer into string")
    let errorResponse = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
    send(client, errorResponse, errorResponse.lengthOfBytes(using: .utf8), 0)
  }

  close(client)
} while sock > -1

close(sock)

func handleCommand(json: [String: Any]) -> Int {

  // print("Received JSONarstrast"
  guard let command = json["command"] as? String else {
    print("Invalid command format")
    return 500
  }

  print("Received command: \(command)")

  switch command {
  case "setPosition":
    if let pid = json["pid"] as? Int,
      let x = json["x"] as? Int,
      let y = json["y"] as? Int,
      let width = json["width"] as? Int,
      let height = json["height"] as? Int
    {
      let frontmostOnly = json["frontmostOnly"] as? Bool
      print("nnnnnnn")

      return setPosition(
        pid: pid_t(pid), frontmostOnly: frontmostOnly, x: x, y: y, width: width, height: height)
    }
  case "focus":
    if let pid = json["pid"] as? Int,
      let title = json["title"] as? String
    {
      print("Focusing window with PID \(pid) and title \(title)")
      return focusWindow(pid: pid_t(pid), title: title)
    }
    return 200
  default:
    print("Unknown command")
    return 400
  }

  return 500
}

func setPosition(pid: pid_t, frontmostOnly: Bool?, x: Int, y: Int, width: Int, height: Int) -> Int {
  let position = CGPoint(x: x, y: y)
  let size = CGSize(width: width, height: height)

  let appRef = AXUIElementCreateApplication(pid)

  if frontmostOnly == true {
    print("front true")

    // Retrieve the frontmost (focused) window
    var frontWindowValue: CFTypeRef?
    let frontWindowResult = AXUIElementCopyAttributeValue(
      appRef, kAXFocusedWindowAttribute as CFString, &frontWindowValue)

    if frontWindowResult == .success, let frontWindow = frontWindowValue as! AXUIElement? {
      // Directly set position and size for the frontmost window
      setPositionAndSizeForWindow(window: frontWindow, position: position, size: size)
      return 200
    } else {
      print("Failed to get the frontmost window for PID: \(pid)")
      return 500
    }
  } else {
    print("front false")
    // Set position and size for all windows
    var allWindowsValue: CFTypeRef?
    let allWindowsResult = AXUIElementCopyAttributeValue(
      appRef, kAXWindowsAttribute as CFString, &allWindowsValue)

    guard allWindowsResult == .success, let windows = allWindowsValue as? [AXUIElement] else {
      print("Failed to get windows for PID: \(pid)")
      return 500
    }
    var didSetPosition = false
    for window in windows {
      setPositionAndSizeForWindow(window: window, position: position, size: size)
      didSetPosition = true
    }

    if !didSetPosition {
      print("No matching window found for PID: \(pid)")
      return 500
    }
  }

  return 200
}

func setPosition(pid: pid_t, x: Int, y: Int, width: Int, height: Int) -> Int {
  let position = CGPoint(x: x, y: y)
  let size = CGSize(width: width, height: height)

  let appRef = AXUIElementCreateApplication(pid)
  var frontWindow: AXUIElement?

  // Retrieve the frontmost (focused) window
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value)

  guard result == .success, let window = value as! AXUIElement? else {
    print("Failed to get the frontmost window for PID: \(pid)")
    return 500
  }

  frontWindow = window

  // Set position and size for the frontmost window
  if let frontWindow = frontWindow {
    setPositionAndSizeForWindow(window: frontWindow, position: position, size: size)
  } else {
    print("No frontmost window found for PID: \(pid)")
    return 500
  }

  return 200
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

func focusWindow(pid: pid_t, title: String? = nil) -> Int {
  // Check if a title is supplied; if not, return 500
  guard let targetTitle = title, !targetTitle.isEmpty else {
    print("No title supplied for PID: \(pid)")
    return 500
  }

  let appRef = AXUIElementCreateApplication(pid)
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)

  guard result == .success, let windows = value as? [AXUIElement], !windows.isEmpty else {
    print("Failed to get windows for PID: \(pid) or no windows available")
    return 500
  }

  var windowFoundAndFocused = false
  for window in windows {
    var titleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)

    // Change the title check to see if the window's title contains the targetTitle
    if let title = titleValue as? String, title.contains(targetTitle) {
      focusAndRaiseWindow(window: window)
      windowFoundAndFocused = true
      break  // Stop after focusing the matching window
    }
  }

  // If no window matching (containing) the title was found, return 500
  if !windowFoundAndFocused {
    print("No matching window found for PID: \(pid) with title containing: \(targetTitle)")
    return 500
  }

  // Successfully focused a window
  return 200
}

// Helper function to focus and raise a window
func focusAndRaiseWindow(window: AXUIElement) {
  AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
  AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  print("Window focused and raised.")
}
