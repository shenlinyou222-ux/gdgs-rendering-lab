# 素材来源与署名

- `8k_stars_milky_way.jpg`(8192x4096,天空球):Solar System Scope,CC BY 4.0
  https://www.solarsystemscope.com/textures/download/8k_stars_milky_way.jpg
- `8k_jupiter.jpg`(4096x2048,木星):Solar System Scope,CC BY 4.0
  https://www.solarsystemscope.com/textures/download/8k_jupiter.jpg
- `nebula/PIA03096.jpg`(创造之柱,Towering Infernos,1920x1427):NASA 公版
  https://images-assets.nasa.gov/image/PIA03096/PIA03096~large.jpg
- `nebula/PIA25434.jpg`(猎户座星云红外,1920x1624):NASA 公版
  https://images-assets.nasa.gov/image/PIA25434/PIA25434~large.jpg
- `nebula/carina_nebula.jpg`(JWST 宇宙悬崖,1920x1111):NASA 公版
  https://images-assets.nasa.gov/image/carina_nebula/carina_nebula~large.jpg
- `nasa_sky_panorama_8k.jpg`(8192x4096,360°全景):由上述 3 张 NASA 公版星云图经
  `tools/make_sky_panorama.py` 程序化拼接生成(加法混合+羽化+程序化星点),底层素材均为 NASA 公版
- `nasa_svs/starmap_2020_4k.exr`(4096x2048 HDR 全天图):NASA 公版
  https://svs.gsfc.nasa.gov/4851/ — "Courtesy of NASA/Goddard Space Flight Center Scientific Visualization Studio"
  (Godot 原生导入 EXR;在 dual_panorama_sky.gdshader 中作为全向星场地基与拼接全景相加)
- `demo.compressed.ply`(27.1万高斯点样例):ReconWorldLab/godot-gaussian-splatting Releases,MIT
- 计划替换:NASA SVS Deep Star Maps 2020(公版,EXR 需色调映射后转 JPG/PNG)
  https://svs.gsfc.nasa.gov/4851/ — "Courtesy of NASA/Goddard Space Flight Center Scientific Visualization Studio"
- planets/earth.jpg (5400x2700, 地球): NASA 公版 Blue Marble (world.topo.bathy.200412, 含地形/海深, 无云)
  https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/world.topo.bathy.200412.3x5400x2700.jpg
  (2026-09-10 由 2K SSC 版就地替换; 原版备份于 experiment/asset_backups_20260910/earth_2k.jpg)
- 注: planets/earth.jpg 于 2026-09-10 追加程序化调色(gamma 0.62 提亮+饱和 1.35+蓝通道 1.12), 源为同一 NASA 公版图, 以匹配游戏美术基调
