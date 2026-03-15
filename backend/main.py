from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, Tuple, List
from screenshot_service import ScreenshotService
import os

app = FastAPI()
service = ScreenshotService()

class CaptureRequest(BaseModel):
    monitor_index: int = 1
    region: Optional[Tuple[int, int, int, int]] = None  # (left, top, width, height)
    base_name: str = "screenshot"
    naming_pattern: int = 1
    sub_dir: str = "default"
    quality: int = 85
    resize_to: Optional[Tuple[int, int]] = None

class BatchResizeRequest(BaseModel):
    file_paths: List[str]
    target_size: Tuple[int, int]
    quality: int = 85

@app.get("/monitors")
async def get_monitors():
    return service.get_monitor_info()

@app.get("/groups")
async def get_groups():
    try:
        groups = [d for d in os.listdir(service.save_dir) if os.path.isdir(os.path.join(service.save_dir, d))]
        if "default" not in groups:
            os.makedirs(os.path.join(service.save_dir, "default"), exist_ok=True)
            groups.append("default")
        return {"base_dir": service.save_dir, "groups": sorted(groups)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class GroupCreateRequest(BaseModel):
    name: str

@app.post("/groups")
async def create_group(req: GroupCreateRequest):
    try:
        target = os.path.join(service.save_dir, req.name)
        os.makedirs(target, exist_ok=True)
        return {"status": "success", "group": req.name}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/files/{group_name}")
async def get_files(group_name: str):
    target = os.path.join(service.save_dir, group_name)
    if not os.path.exists(target):
        return {"files": []}
    files = [f for f in os.listdir(target) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
    # Sort files by creation time conceptually (here by name is ok)
    files.sort(reverse=True)
    return {"files": files}

@app.delete("/files/{group_name}/{file_name}")
async def delete_file(group_name: str, file_name: str):
    target = os.path.join(service.save_dir, group_name, file_name)
    if os.path.exists(target):
        os.remove(target)
        return {"status": "success"}
    raise HTTPException(status_code=404, detail="File not found")

class ConfigRequest(BaseModel):
    base_save_dir: str

@app.post("/config")
async def update_config(req: ConfigRequest):
    try:
        os.makedirs(req.base_save_dir, exist_ok=True)
        service.save_dir = req.base_save_dir
        return {"status": "success", "base_dir": service.save_dir}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/images/{group_name}/{file_name}")
async def get_image(group_name: str, file_name: str):
    target = os.path.join(service.save_dir, group_name, file_name)
    if os.path.exists(target):
        return FileResponse(target)
    raise HTTPException(status_code=404, detail="Image not found")

@app.post("/capture")
async def capture_screen(request: CaptureRequest):
    try:
        path = service.capture(
            monitor_index=request.monitor_index,
            region=request.region,
            base_name=request.base_name,
            naming_pattern=request.naming_pattern,
            quality=request.quality,
            resize_to=request.resize_to,
            sub_dir=request.sub_dir
        )
        return {"status": "success", "path": path}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/batch_resize")
async def batch_resize(request: BatchResizeRequest):
    try:
        service.batch_resize(
            file_paths=request.file_paths,
            target_size=request.target_size,
            quality=request.quality
        )
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
