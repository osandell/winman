#!/usr/bin/env python3
import socket
import json
import threading
from Xlib import X, display, Xutil, error
from Xlib.protocol import event
import sys
import os
import subprocess

class X11WindowManager:
    def __init__(self):
        self.display = display.Display()
        self.root = self.display.screen().root
        
    def debug_window_info(self, window):
        """Print debug info about a window."""
        try:
            pid = self.get_window_pid(window)
            name = window.get_wm_name()
            wm_class = window.get_wm_class()
            print(f"Window info - PID: {pid}, Name: {name}, Class: {wm_class}")
            return True
        except:
            return False

    def list_all_windows(self):
        """List all windows and their PIDs for debugging."""
        print("\nListing all windows:")
        windows = self.get_all_windows()
        for window in windows:
            self.debug_window_info(window)
        print("End window list\n")

    def get_all_windows(self):
        """Get all windows."""
        windows = []
        try:
            # Try _NET_CLIENT_LIST first
            window_ids = self.root.get_full_property(
                self.display.intern_atom('_NET_CLIENT_LIST'),
                X.AnyPropertyType
            )
            
            if window_ids:
                for window_id in window_ids.value:
                    try:
                        window = self.display.create_resource_object('window', window_id)
                        if self.is_valid_window(window):
                            windows.append(window)
                    except error.BadWindow:
                        continue
            
            # Fallback to _NET_CLIENT_LIST_STACKING if needed
            if not windows:
                window_ids = self.root.get_full_property(
                    self.display.intern_atom('_NET_CLIENT_LIST_STACKING'),
                    X.AnyPropertyType
                )
                if window_ids:
                    for window_id in window_ids.value:
                        try:
                            window = self.display.create_resource_object('window', window_id)
                            if self.is_valid_window(window):
                                windows.append(window)
                        except error.BadWindow:
                            continue
                            
        except Exception as e:
            print(f"Error getting window list: {e}")
            
        return windows

    def is_valid_window(self, window):
        """Check if a window is valid and should be included."""
        try:
            attrs = window.get_attributes()
            return attrs.map_state == X.IsViewable
        except:
            return False

    def strip_parens(self, title):
        """Remove trailing parentheses and any whitespace before them."""
        if not title:
            return title
        return title.split(' (')[0].strip()

    def normalize_title(self, title):
        """Convert between ~ and /home/user representations of the title."""
        if not title:
            return [title]
            
        # First strip any trailing parentheses
        base_title = self.strip_parens(title)
        
        # Replace ~ with /home/olof
        expanded = base_title.replace("~/", "/home/olof/")
        # Replace /home/olof with ~
        shortened = base_title.replace("/home/olof/", "~/")
        
        return [base_title, expanded, shortened]

    def get_window_title(self, window):
        """Get window title trying multiple methods."""
        try:
            # Try _NET_WM_NAME first
            net_wm_name = window.get_full_property(
                self.display.intern_atom('_NET_WM_NAME'),
                self.display.intern_atom('UTF8_STRING')
            )
            if net_wm_name and net_wm_name.value:
                return self.strip_parens(net_wm_name.value.decode('utf-8'))
                
            # Fallback to WM_NAME
            wm_name = window.get_full_property(
                self.dsplay.intern_atom('WM_NAME'),
                self.display.intern_atom('STRING')
            )
            if wm_name and wm_name.value:
                return self.strip_parens(wm_name.value.decode('utf-8'))
                
        except Exception as e:
            print(f"Error getting window title: {e}")
        
        # Fallback to get_wm_name, strip parens from result
        title = window.get_wm_name() or ""
        return self.strip_parens(title)

    def get_frontmost_window(self, windows):
        """Get the frontmost window from a list of windows using stacking order."""
        try:
            stacking = self.root.get_full_property(
                self.display.intern_atom('_NET_CLIENT_LIST_STACKING'),
                X.AnyPropertyType
            )
            if stacking:
                # Convert window IDs to actual windows and reverse to get top-to-bottom order
                stacked_windows = [
                    self.display.create_resource_object('window', win_id)
                    for win_id in reversed(stacking.value)
                ]
                # Find the highest (frontmost) window from our list
                for window in stacked_windows:
                    if any(w.id == window.id for w in windows):
                        print(f"\nFound frontmost window:")
                        print(f"  Window ID: {window.id}")
                        print(f"  Title: '{self.get_window_title(window)}'")
                        return window
        except Exception as e:
            print(f"Error finding frontmost window: {e}")
        return None

    def get_window_by_pid(self, pid, title=None, frontmost_only=False):
        """Find window(s) belonging to a specific PID."""
        seen_window_ids = set()
        pid_windows = []
        print(f"\nLooking for windows with PID: {pid}")
        
        # First collect all windows for this PID
        for window in self.get_all_windows():
            try:
                if window.id in seen_window_ids:
                    continue
                    
                window_pid = self.get_window_pid(window)
                if window_pid == pid:
                    seen_window_ids.add(window.id)
                    pid_windows.append(window)
                    print(f"\nFound window:")
                    print(f"  Window ID: {window.id}")
                    print(f"  Title: '{self.get_window_title(window)}'")
                    
            except Exception as e:
                print(f"Error checking window: {e}")
                continue

        print(f"\nFound {len(pid_windows)} unique windows for PID {pid}")

        if not pid_windows:
            print(f"No windows found for PID: {pid}")
            return []

        # Filter by title if specified
        if title:
            possible_titles = self.normalize_title(title)
            print(f"Trying to match against variations: {possible_titles}")
            matching_windows = []
            for window in pid_windows:
                window_title = self.get_window_title(window)
                if window_title in possible_titles:
                    matching_windows.append(window)
            pid_windows = matching_windows
            
            if not pid_windows:
                print(f"No windows match title: {title}")
                return []

        # If frontmost_only, return only the frontmost window
        if frontmost_only:
            frontmost = self.get_frontmost_window(pid_windows)
            return [frontmost] if frontmost else []
            
        return pid_windows

    def get_window_pid(self, window):
        """Get the PID of a window."""
        try:
            # Try _NET_WM_PID first
            pid = window.get_full_property(
                self.display.intern_atom('_NET_WM_PID'),
                X.AnyPropertyType
            )
            if pid:
                return pid.value[0]
            
            # Fallback: try getting PID from window class
            wm_class = window.get_wm_class()
            if wm_class:
                # Try getting PID by process name
                try:
                    output = subprocess.check_output(['pgrep', '-f', wm_class[0]]).decode()
                    return int(output.split()[0])
                except:
                    pass
                    
        except:
            pass
        return None

    def get_active_window(self):
        """Get the currently active window."""
        try:
            active_window_id = self.root.get_full_property(
                self.display.intern_atom('_NET_ACTIVE_WINDOW'),
                X.AnyPropertyType
            ).value[0]
            return self.display.create_resource_object('window', active_window_id)
        except:
            return None

    def set_window_position(self, window, x, y, width, height):
        """Set position and size of a window."""
        try:
            # Get current geometry
            geom = window.get_geometry()
            
            # Use provided values or fall back to current geometry
            new_x = x if x is not None else geom.x
            new_y = y if y is not None else geom.y
            new_width = width if width is not None else geom.width
            new_height = height if height is not None else geom.height
            
            print(f"Setting window position: x={new_x}, y={new_y}, width={new_width}, height={new_height}")
            
            # Get window's current state
            state = window.get_full_property(
                self.display.intern_atom('_NET_WM_STATE'),
                X.AnyPropertyType
            )
            print(f"Window state: {state}")
            
            # If window is maximized, unmaximize it first
            if state and (
                self.display.intern_atom('_NET_WM_STATE_MAXIMIZED_VERT') in state.value or
                self.display.intern_atom('_NET_WM_STATE_MAXIMIZED_HORZ') in state.value
            ):
                print("Unmaximizing window first")
                self._unmaximize_window(window)
            
            # Set the new position and size
            window.configure(
                x=new_x,
                y=new_y,
                width=new_width,
                height=new_height
            )

            print(f"Window state after unmaximize: {window.get_full_property(self.display.intern_atom('_NET_WM_STATE'), X.AnyPropertyType)}")
            
            self.display.sync()
            print(f"Window state after sync: {window.get_full_property(self.display.intern_atom('_NET_WM_STATE'), X.AnyPropertyType)}")
            return True
            
        except Exception as e:
            print(f"Error setting window position: {e}")
            return False

    def _unmaximize_window(self, window):
        from Xlib.protocol import event as xlib_event 

        """Helper function to unmaximize a window."""
        maximize_vert = self.display.intern_atom('_NET_WM_STATE_MAXIMIZED_VERT')
        maximize_horz = self.display.intern_atom('_NET_WM_STATE_MAXIMIZED_HORZ')
        wm_state = self.display.intern_atom('_NET_WM_STATE')
        
        # Create unmaximize event
        event_data = [
            0,  # _NET_WM_STATE_REMOVE
            maximize_vert,
            maximize_horz,
            1  # normal application
        ]
        
        event = xlib_event.ClientMessage(
            window=window,
            client_type=wm_state,
             data=(32, [0, maximize_vert, maximize_horz, 1, 0])
        )
        
        # Send event
        mask = X.SubstructureRedirectMask | X.SubstructureNotifyMask
        self.root.send_event(event, event_mask=mask)
        self.display.sync()

    def focus_window(self, window):
        """Focus a specific window."""
        try:
            print("Focusing window")
            window.set_input_focus(X.RevertToParent, X.CurrentTime)
            window.configure(stack_mode=X.Above)
            self.display.sync()
            return True
        except Exception as e:
            print(f"Error focusing window: {e}")
            return False

class WindowServer:
    def __init__(self, port=57320):
        self.port = port
        self.wm = X11WindowManager()
        print("X11 Window Manager initialized")
        self.wm.list_all_windows()
        
    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('', self.port))
        server.listen(5)
        print(f"Server is listening on port {self.port}")
        
        while True:
            client, addr = server.accept()
            threading.Thread(target=self.handle_client, args=(client,)).start()
    
    def handle_client(self, client):
        try:
            data = client.recv(1024).decode('utf-8')
            print("\nRaw request data:")
            print("=" * 50)
            print(data)
            print("=" * 50)
            
            if not data:
                return self.send_response(client, 400)
            
            try:
                headers, body = data.split('\r\n\r\n', 1)
                print("\nRequest headers:")
                print(headers)
                print("\nRequest body:")
                print(body)
                
                json_data = json.loads(body)
                print(f"\nParsed JSON data: {json_data}")
                
            except Exception as e:
                print(f"Error parsing request: {e}")
                print(f"Error type: {type(e)}")
                print(f"Error occurred at line {e.__traceback__.tb_lineno}")
                return self.send_response(client, 400)
            
            status_code = self.handle_command(json_data)
            self.send_response(client, status_code)
            
        except Exception as e:
            print(f"Error handling client: {e}")
            self.send_response(client, 500)
        finally:
            client.close()
    
    def send_response(self, client, status_code):
        response = f"HTTP/1.1 {status_code} {self.get_status_text(status_code)}\r\nContent-Length: 0\r\n\r\n"
        client.send(response.encode('utf-8'))
    
    def get_status_text(self, status_code):
        status_texts = {
            200: "OK",
            400: "Bad Request",
            500: "Internal Server Error"
        }
        return status_texts.get(status_code, "Unknown")
    
    def handle_command(self, json_data):
        try:
            command = json_data.get("command")
            pid = json_data.get("pid")
            
            if not command or not pid:
                print("Missing command or PID")
                return 400
            
            print(f"Handling command: {command} for PID: {pid}")
            
            if command == "setPosition":
                x = json_data.get("x")
                y = json_data.get("y")
                width = json_data.get("width")
                height = json_data.get("height")
                frontmost_only = json_data.get("frontmostOnly", False)
                
                windows = self.wm.get_window_by_pid(pid, frontmost_only=frontmost_only)
                if not windows:
                    return 500
                
                success = all(
                    self.wm.set_window_position(window, x, y, width, height)
                    for window in windows
                )
                return 200 if success else 500
            
            elif command == "focus":
                title = json_data.get("title")
                if not title:
                    print("Missing title for focus command")
                    return 400
                
                windows = self.wm.get_window_by_pid(pid, title=title)
                if not windows:
                    return 500
                
                success = self.wm.focus_window(windows[0])
                return 200 if success else 500
            
            else:
                print(f"Unknown command: {command}")
                return 400
                
        except Exception as e:
            print(f"Error handling command: {e}")
            return 500

if __name__ == "__main__":
    # Check if DISPLAY is set
    if not os.environ.get('DISPLAY'):
        print("Error: DISPLAY environment variable not set")
        print("Make sure you're running in an X11 session")
        sys.exit(1)
        
    # Check if we can connect to X server
    try:
        display.Display()
    except Exception as e:
        print("Error: Cannot connect to X server")
        print(f"Details: {e}")
        sys.exit(1)
    
    server = WindowServer()
    try:
        server.start()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        sys.exit(0)
    except Exception as e:
        print(f"Failed to start server: {e}")
        sys.exit(1)
