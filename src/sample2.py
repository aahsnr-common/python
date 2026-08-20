import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

import numpy as np

@dataclass
class Task:
    id: int
