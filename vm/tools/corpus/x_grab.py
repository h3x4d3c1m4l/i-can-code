import ctypes
import json
import time
import tkinter as tk

# Another X client grabs the server, so no other client is served until it lets go, and maps
# windows meanwhile. The first map sets the agent's X watcher waiting on a reply; the next one
# arrives during that wait.
x = ctypes.CDLL("libX11.so.6")
x.XOpenDisplay.restype = ctypes.c_void_p
x.XOpenDisplay.argtypes = [ctypes.c_char_p]
for name in ("XGrabServer", "XUngrabServer"):
    getattr(x, name).argtypes = [ctypes.c_void_p]
x.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint,
                                  ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
x.XCreateSimpleWindow.restype = ctypes.c_ulong
x.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x.XCreateGC.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
x.XCreateGC.restype = ctypes.c_void_p
x.XSetForeground.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong]
x.XFillRectangle.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_uint, ctypes.c_uint]

root = tk.Tk()
root.title("Grab")
tk.Label(root, text="The server is mine for a moment").pack(padx=20, pady=20)
root.update()
time.sleep(1)
display = x.XOpenDisplay(None)


def window(left, colour):
    new = x.XCreateSimpleWindow(display, x.XDefaultRootWindow(display), left, 300, 100, 100, 0, 0, colour)
    x.XMapWindow(display, new)
    x.XSync(display, 0)
    return new


# A short grab: well within the host's PONG deadline.
x.XGrabServer(display)
x.XSync(display, 0)
first = window(20, 0xFF8800)
time.sleep(0.1)
second = window(140, 0x88FF00)
time.sleep(0.3)
x.XUngrabServer(display)
x.XSync(display, 0)
# Drawing into a window of its own tells the host the grab is over and sends the agent nothing.
pen = x.XCreateGC(display, first, 0, None)
x.XSetForeground(display, pen, 0x0000FF)
x.XFillRectangle(display, first, pen, 0, 0, 100, 100)
x.XSync(display, 0)
# Nothing printed for a while: output would wake the agent too.
time.sleep(3)
print(json.dumps({"first": first, "second": second}), flush=True)

# A long grab: longer than the host waits for a PONG.
x.XGrabServer(display)
x.XSync(display, 0)
print("grabbed", flush=True)
third = window(260, 0x00FF88)
time.sleep(6)
x.XUngrabServer(display)
x.XSync(display, 0)
print(json.dumps({"released": third}), flush=True)
root.after(1000, root.destroy)
root.mainloop()
print("done", flush=True)
