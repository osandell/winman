# README for Swift Server Application

This README document provides an overview of a Swift server application that listens for incoming connections on a specified port, accepts commands, and manipulates window positions and focus based on those commands. The application is designed to run on macOS, utilizing Application Services and Cocoa frameworks for window manipulation.

## Requirements

- macOS operating system
- Swift 5 or higher
- Xcode or another Swift compiler setup

## Installation

Clone the repository or download the source code. Open your terminal, navigate to the project directory, and compile the Swift file. Ensure you have Swift installed on your machine.

## Usage

1. Compile the Swift file using Xcode or the Swift compiler.
2. Run the compiled application from the terminal.
3. The server listens on port 57320 for incoming connections. Use a client to send commands to the server.
4. Supported commands include setting window position and focusing a window. Commands should be formatted in JSON and sent over the network to the server.

### Command Format

Commands should be sent as JSON strings with the following format:

```json
{
  "command": "setPosition",
  "pid": [Process ID],
  "x": [X Position],
  "y": [Y Position],
  "width": [Width],
  "height": [Height],
  "title": "[Window Title (optional)]"
}
```

or

```json
{
  "command": "focus",
  "pid": [Process ID],
  "title": "[Window Title]"
}
```

## Features

- **Socket Programming**: Utilizes low-level socket APIs for network communication.
- **Window Manipulation**: Interfaces with macOS Accessibility APIs to manipulate window positions and focus based on external commands.
- **JSON Parsing**: Parses JSON formatted commands to perform specified actions.

## Limitations

- The application must be granted Accessibility permissions to manipulate window positions and focus.
- Currently, only supports macOS due to the usage of macOS specific APIs.

## License

This project is open-source and available under the MIT License.

