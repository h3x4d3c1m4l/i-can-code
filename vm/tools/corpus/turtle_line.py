import json
import turtle

screen = turtle.Screen()
pen = turtle.Turtle()
pen.color("#0000ff")
pen.pensize(9)
pen.forward(100)
canvas = screen.getcanvas()._canvas
canvas.update()
# Turtle (50, 0), halfway along the line. Turtle's origin is wherever the canvas scrolled it to.
x = canvas.winfo_rootx() + round(50 - canvas.canvasx(0))
y = canvas.winfo_rooty() + round(0 - canvas.canvasy(0))
print(json.dumps({"line": [x, y]}), flush=True)
turtle.done()
