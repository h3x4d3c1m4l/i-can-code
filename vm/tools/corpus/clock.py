import time
from datetime import datetime

print(f"{time.time() * 1000:.0f} {datetime.now().isoformat()} {time.strftime('%z')}", flush=True)
