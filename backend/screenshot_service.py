import os
import mss
import mss.tools
from PIL import Image
from typing import Optional, List, Tuple
from datetime import datetime

class ScreenshotService:
    def __init__(self, save_dir: str = "screenshots"):
        self.save_dir = os.path.abspath(save_dir)
        if not os.path.exists(self.save_dir):
            os.makedirs(self.save_dir)
            
    def get_monitor_info(self) -> List[dict]:
        with mss.mss() as sct:
            return sct.monitors

    def capture(self, 
                monitor_index: int = 0, 
                region: Optional[Tuple[int, int, int, int]] = None, 
                base_name: str = "screenshot", 
                naming_pattern: int = 1,
                quality: int = 85,
                resize_to: Optional[Tuple[int, int]] = None,
                sub_dir: str = "default") -> str:
        """
        monitor_index: 0 is all monitors combined, 1 is first monitor, etc.
        region: (left, top, width, height)
        """
        with mss.mss() as sct:
            if region:
                monitor = {
                    "top": region[1],
                    "left": region[0],
                    "width": region[2],
                    "height": region[3],
                }
            else:
                monitor = sct.monitors[monitor_index]

            sct_img = sct.grab(monitor)
            
            # Convert to PIL Image
            img = Image.frombytes("RGB", sct_img.size, sct_img.bgra, "raw", "BGRX")
            
            # Apply Resize if needed
            if resize_to:
                img = img.resize(resize_to, Image.Resampling.LANCZOS)
                
            # Create Sequential Name
            filename = self._generate_filename(base_name, naming_pattern)
            filepath = os.path.join(self.save_dir, filename)
            
            # Save with compression
            img.save(filepath, "JPEG", quality=quality)
            return filepath

        target_dir = os.path.join(self.save_dir, sub_dir)
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)

        now_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        count = 1
        while True:
            if naming_pattern == 1:
                # 1. Prefix + Sequential
                filename = f"{base_name}_{count:02d}.jpg"
            elif naming_pattern == 2:
                # 2. DateTime Only
                filename = f"{now_str}.jpg" if count == 1 else f"{now_str}({count}).jpg"
            elif naming_pattern == 3:
                # 3. DateTime + Sequential
                filename = f"{now_str}_{count:02d}.jpg"
            elif naming_pattern == 4:
                # 4. Prefix + DateTime
                filename = f"{base_name}_{now_str}.jpg" if count == 1 else f"{base_name}_{now_str}({count}).jpg"
            elif naming_pattern == 5:
                # 5. Prefix + DateTime + Sequential
                filename = f"{base_name}_{now_str}_{count:02d}.jpg"
            else:
                # Fallback to pattern 1
                filename = f"{base_name}_{count:02d}.jpg"

            if not os.path.exists(os.path.join(target_dir, filename)):
                return filename
            count += 1

    def capture(self, 
                monitor_index: int = 0, 
                region: Optional[Tuple[int, int, int, int]] = None, 
                base_name: str = "screenshot", 
                naming_pattern: int = 1,
                quality: int = 85,
                resize_to: Optional[Tuple[int, int]] = None,
                sub_dir: str = "default") -> str:
        """
        monitor_index: 0 is all monitors combined, 1 is first monitor, etc.
        region: (left, top, width, height)
        """
        with mss.mss() as sct:
            if region:
                monitor = {
                    "top": region[1],
                    "left": region[0],
                    "width": region[2],
                    "height": region[3],
                }
            else:
                monitor = sct.monitors[monitor_index]

            sct_img = sct.grab(monitor)
            
            # Convert to PIL Image
            img = Image.frombytes("RGB", sct_img.size, sct_img.bgra, "raw", "BGRX")
            
            # Apply Resize if needed
            if resize_to:
                img = img.resize(resize_to, Image.Resampling.LANCZOS)
                
            # Create Sequential Name
            target_dir = os.path.join(self.save_dir, sub_dir)
            if not os.path.exists(target_dir):
                os.makedirs(target_dir)
                
            filename = self._generate_filename(base_name, naming_pattern, sub_dir)
            filepath = os.path.join(target_dir, filename)
            
            # Save with compression
            img.save(filepath, "JPEG", quality=quality)
            return filepath

    def _generate_filename(self, base_name: str, naming_pattern: int, sub_dir: str) -> str:
        target_dir = os.path.join(self.save_dir, sub_dir)
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)

        now_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        count = 1
        while True:
            if naming_pattern == 1:
                # 1. Prefix + Sequential
                filename = f"{base_name}_{count:02d}.jpg"
            elif naming_pattern == 2:
                # 2. DateTime Only
                filename = f"{now_str}.jpg" if count == 1 else f"{now_str}({count}).jpg"
            elif naming_pattern == 3:
                # 3. DateTime + Sequential
                filename = f"{now_str}_{count:02d}.jpg"
            elif naming_pattern == 4:
                # 4. Prefix + DateTime
                filename = f"{base_name}_{now_str}.jpg" if count == 1 else f"{base_name}_{now_str}({count}).jpg"
            elif naming_pattern == 5:
                # 5. Prefix + DateTime + Sequential
                filename = f"{base_name}_{now_str}_{count:02d}.jpg"
            else:
                # Fallback to pattern 1
                filename = f"{base_name}_{count:02d}.jpg"

            if not os.path.exists(os.path.join(target_dir, filename)):
                return filename
            count += 1

    def batch_resize(self, file_paths: List[str], target_size: Tuple[int, int], quality: int = 85):
        for path in file_paths:
            if os.path.exists(path):
                img = Image.open(path)
                img = img.resize(target_size, Image.Resampling.LANCZOS)
                img.save(path, "JPEG", quality=quality)
