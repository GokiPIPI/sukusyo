import sys

def analyze_log():
    try:
        content = ""
        try:
            with open('log.txt', 'r', encoding='utf-16-le') as f:
                content = f.read()
        except:
            with open('log.txt', 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
        lines = content.splitlines()
        with open('errors.txt', 'w', encoding='utf-8') as out:
            for i, line in enumerate(lines):
                if "error" in line.lower() or "exception" in line.lower() or "fail" in line.lower():
                    out.write(f"Line {i}: {line.strip()}\n")
                    for j in range(max(0, i-2), min(len(lines), i+3)):
                        out.write(f"  {lines[j].strip()}\n")
                    out.write("-" * 20 + "\n")
    except Exception as e:
        with open('errors.txt', 'w', encoding='utf-8') as out:
            out.write(f"Error reading log: {e}")

if __name__ == "__main__":
    analyze_log()
