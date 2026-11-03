"""Record the depotOS demo page (depotos-demo.html) to a 1080p MP4.

usage:
  python record_demo.py video  <out.mp4>          # full walkthrough (~2:38)
  python record_demo.py short  <out.mp4>          # 30-second cut   (#short)
  python record_demo.py promo  <out.mp4>          # 45-second promo (#promo)
  python record_demo.py motion-vertical <out.mp4> # the 3D cut in 9:16 (1080x1920) for Reels / WhatsApp Status
  python record_demo.py motion <out.mp4>          # 45-second 3D motion cut (#motion), rendered frame by frame
  python record_demo.py stills <cut> <outdir> <seconds...>   # still frames from a cut, for checking

Needs: pip install playwright imageio-ffmpeg  (and `playwright install chromium`).
"""
import asyncio, base64, pathlib, subprocess, sys, time

import imageio_ffmpeg
from playwright.async_api import async_playwright

HERE = pathlib.Path(__file__).parent
FPS = 30
W, H, SCALE = 1280, 720, 1.5          # CSS viewport x device scale = 1920x1080 output
CUTS = ("short", "promo", "motion")

# The published artifact is wrapped in a standards-mode skeleton; do the same locally
# (without a doctype, tables fall back to quirks mode and lose their text colour).
_SRC = (HERE / "depotos-demo.html").read_text(encoding="utf-8")
_REC = HERE / "_record_page.html"
_REC.write_text('<!doctype html><html><head><meta charset="utf-8">'
                '<meta name="viewport" content="width=device-width,initial-scale=1">'
                '<style>body{margin:0}</style></head><body>' + _SRC + '</body></html>', encoding="utf-8")
PAGE = _REC.as_uri()


async def open_player(p, cut=None):
    browser = await p.chromium.launch()
    ctx = await browser.new_context(viewport={"width": W, "height": H}, device_scale_factor=SCALE)
    page = await ctx.new_page()
    await page.goto(PAGE + (f"#{cut}" if cut else ""), wait_until="networkidle")
    await page.evaluate("document.fonts.ready.then(() => true)")
    await page.wait_for_timeout(1200)  # let the page's own autoplay timer fire, then take control
    # Present mode: hides the player controls and chapter list, keeps captions and contact line.
    await page.evaluate("() => { player.classList.add('present'); setPlaying(false); fit(); }")
    return browser, ctx, page


async def stills(cut, outdir, moments):
    out = pathlib.Path(outdir); out.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        browser, ctx, page = await open_player(p, cut)
        await page.evaluate("() => go(0)")
        start = await page.evaluate("performance.now()")
        for m in moments:
            now = await page.evaluate("performance.now()")
            await page.wait_for_timeout(max(0, start + m * 1000 - now))
            await page.screenshot(path=str(out / f"{cut}_{m:04.1f}s.png"))
        await browser.close()


async def video(out_path, cut=None):
    hold = 0.4 if cut else 2.5
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    proc = subprocess.Popen(
        [ffmpeg, "-y", "-loglevel", "error",
         "-f", "image2pipe", "-framerate", str(FPS), "-c:v", "mjpeg", "-i", "-",
         "-vf", f"scale={int(W*SCALE)}:{int(H*SCALE)}:flags=lanczos,format=yuv420p",
         "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-tune", "stillimage" if cut != "motion" else "film",
         "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE)

    st = {"t0": None, "last": None, "written": 0}

    def write_until(ts):
        # Turn the variable-rate screencast into constant 30 fps by repeating the latest frame.
        target = int((ts - st["t0"]) * FPS)
        while st["last"] is not None and st["written"] < target:
            proc.stdin.write(st["last"]); st["written"] += 1

    async with async_playwright() as p:
        browser, ctx, page = await open_player(p, cut)
        cdp = await ctx.new_cdp_session(page)

        def on_frame(ev):
            asyncio.ensure_future(cdp.send("Page.screencastFrameAck", {"sessionId": ev["sessionId"]}))
            ts = ev["metadata"]["timestamp"]
            if st["t0"] is None:
                st["t0"] = ts
            write_until(ts)
            st["last"] = base64.b64decode(ev["data"])

        cdp.on("Page.screencastFrame", on_frame)
        await cdp.send("Page.startScreencast", {"format": "jpeg", "quality": 95,
                                                "maxWidth": int(W*SCALE), "maxHeight": int(H*SCALE), "everyNthFrame": 1})
        await page.evaluate("() => go(0)")
        total = await page.evaluate("TOTAL")
        print(f"recording ~{total/1000:.0f}s ...", flush=True)
        while not await page.evaluate("ended"):
            await asyncio.sleep(0.5)
        # The screencast only emits frames when pixels change, so a still closing scene
        # produces none: pad up to "now" with the last frame (timestamps are epoch seconds).
        write_until(time.time())
        await cdp.send("Page.stopScreencast")
        for _ in range(int(hold * FPS)):         # hold the closing frame briefly
            proc.stdin.write(st["last"])
        await browser.close()

    proc.stdin.close()
    proc.wait()
    print("frames:", st["written"] + int(hold * FPS), "exit:", proc.returncode)


async def render(out_path, cut, hold=0.4):
    """Frame-by-frame render: the page's clock is advanced exactly 1/FPS per frame (window.__tick),
    so heavy 3D scenes come out smooth and correctly timed even without a GPU. Slower than real time."""
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    proc = subprocess.Popen(
        [ffmpeg, "-y", "-loglevel", "error",
         "-f", "image2pipe", "-framerate", str(FPS), "-c:v", "mjpeg", "-i", "-",
         "-vf", f"scale={int(W*SCALE)}:{int(H*SCALE)}:flags=lanczos,format=yuv420p",
         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE)
    async with async_playwright() as p:
        browser, ctx, page = await open_player(p, cut)
        cdp = await ctx.new_cdp_session(page)
        total = await page.evaluate("TOTAL")
        n = int(round((total / 1000 + hold) * FPS))
        await page.evaluate("() => { window.__manual = true; go(0); }")
        started = time.time()
        for i in range(n):
            await page.evaluate(f"__tick({1000 / FPS})")
            shot = await cdp.send("Page.captureScreenshot", {"format": "jpeg", "quality": 92})
            proc.stdin.write(base64.b64decode(shot["data"]))
            if i % 150 == 0:
                print(f"frame {i}/{n}  ({time.time() - started:.0f}s elapsed)", flush=True)
        await browser.close()
    proc.stdin.close()
    proc.wait()
    print("frames:", n, "exit:", proc.returncode)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "stills":
        asyncio.run(stills(sys.argv[2], sys.argv[3], [float(x) for x in sys.argv[4:]]))
    elif mode == "motion":
        asyncio.run(render(sys.argv[2], "motion"))
    elif mode == "motion-vertical":
        W, H = 720, 1280
        asyncio.run(render(sys.argv[2], "motion"))
    else:
        asyncio.run(video(sys.argv[2], cut=mode if mode in CUTS else None))
