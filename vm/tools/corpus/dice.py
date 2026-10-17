import os
import random

rolls = [random.randint(1, 6) for _ in range(12)]
print(" ".join(map(str, rolls)), os.urandom(8).hex())
