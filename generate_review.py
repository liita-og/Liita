import os

files_to_dump = [
    "android/app/src/main/kotlin/com/liita/liita/MeshForegroundService.kt",
    "android/app/src/main/kotlin/com/liita/liita/BlePeerRegistry.kt",
    "android/app/src/main/kotlin/com/liita/liita/MeshPlugin.kt",
    "android/app/src/main/AndroidManifest.xml",
    "android/app/src/main/kotlin/com/liita/liita/RelayController.kt",
    "lib/core/controllers/app_controller.dart",
    "lib/core/services/mesh_service_flutter.dart"
]

output = ""

for file_path in files_to_dump:
    if os.path.exists(file_path):
        with open(file_path, "r") as f:
            content = f.read()
        
        ext = file_path.split(".")[-1]
        lang = "kotlin" if ext == "kt" else "xml" if ext == "xml" else "dart"
        
        output += f"### `{file_path.split('/')[-1]}`\n\n"
        output += f"```{lang}\n"
        output += content
        if not content.endswith("\n"):
            output += "\n"
        output += "```\n\n"
    else:
        output += f"### `{file_path.split('/')[-1]}`\n\n"
        output += "*File not found*\n\n"

with open("/Users/pradyumna/.gemini/antigravity/brain/53246201-e7cf-41e7-8cc6-facdab015ecd/ble_layer_code_review.md", "w") as f:
    f.write(output)

print("Generated ble_layer_code_review.md successfully.")
