blocks = []
while True:
    blocks.append(b"x" * (1024 * 1024))
    print(len(blocks), flush=True)
