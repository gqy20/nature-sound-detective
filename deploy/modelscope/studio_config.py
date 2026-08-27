from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
MODELS = ASSETS / "models"
LABELS = ASSETS / "labels"

MAX_AUDIO_SECONDS = 20
MAX_UPLOAD_BYTES = 15 * 1024 * 1024
BIRD_SPECIES_DISPLAY_THRESHOLD = 0.42
SUPPORTED_AUDIO_SUFFIXES = {".aac", ".flac", ".m4a", ".mp3", ".ogg", ".wav", ".webm"}
VERSION = "0.1.0"

GITHUB_URL = "https://github.com/gqy20/nature-sound-detective"
APK_URL = f"{GITHUB_URL}/releases/download/{VERSION}/nature-sound-detective-{VERSION}-android-arm64.apk"
WEB_URL = "https://xykw-web.vercel.app"
STUDIO_DIRECT_URL = "https://gqy2025-nature-sound-detective.ms.show/"

CATEGORY_NAMES = {
    "bird": "鸟类鸣叫",
    "frog": "蛙类鸣叫",
    "insect": "昆虫鸣叫",
    "rain": "雨水",
    "water": "流水",
    "wind": "风和树叶",
    "human": "人声",
    "footsteps": "脚步",
    "traffic": "交通或机械噪声",
}

OBSERVATION_TASKS = {
    "bird": "先不追着声音走。观察它来自树冠、灌木还是地面，再听节奏是否重复。",
    "frog": "和大人保持在安全岸边，听声音来自水面、草丛还是更远的湿地。",
    "insect": "站在原地听十秒：声音是连续的，还是每隔几秒重复一次？",
    "rain": "比较雨滴落在树叶、泥土和屋檐上的音色有什么不同。",
    "water": "在安全距离外判断水声是连续的，还是一阵一阵变化。",
    "wind": "观察树叶摆动，再比较风强弱与声音变化是否同步。",
    "human": "换到更安静的位置重新录制，看看被遮住的自然声能否出现。",
    "footsteps": "停下脚步再录一次，比较前后两段声音有什么变化。",
    "traffic": "远离道路和设备，在安全的人行区域换一个更安静的位置。",
}
