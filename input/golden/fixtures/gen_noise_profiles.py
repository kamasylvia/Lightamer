#!/usr/bin/env python3
"""
gen_noise_profiles.py — dt noiseprofiles.json → Lightamer bundle 规范化转换.

D-05-CONTEXT-2（构建期转换）：读 darktable `data/noiseprofiles.json` →
规范化输出 `LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json` —
makers/models 字典序、profiles 按 ISO 升序、a[3]/b[3] 浮点显式、skip 档
保留（skip:true 档原样保留，由加载器跳过——与 dt noiseprofiles.c 语义一致）、
version 字段保留。规避运行时键序/浮点解析差异（L013 精神；剖面不进身份，
风险低）。

自校验（转换前后）：每 model 档数守恒 + 抽 3 model 逐值 diff。

Usage:
  gen_noise_profiles.py [DT_JSON] [OUT_JSON]
  默认 DT_JSON = /path/to/darktable/data/noiseprofiles.json
  默认 OUT_JSON = LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json（相对仓库根）
"""

import json
import os
import sys

DEFAULT_DT = "/path/to/darktable/data/noiseprofiles.json"

def repo_root() -> str:
    # input/golden/fixtures/ → 仓库根上四级（input/golden/fixtures → 根）
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

def normalize(dt_path: str) -> dict:
    with open(dt_path, "r", encoding="utf-8") as f:
        dt = json.load(f)
    makers = []
    for maker_entry in dt["noiseprofiles"]:
        models = []
        for model in maker_entry["models"]:
            profiles = []
            for p in model["profiles"]:
                profiles.append({
                    "name": p["name"],
                    "iso": p["iso"],
                    "a": [float(v) for v in p["a"]],
                    "b": [float(v) for v in p["b"]],
                    **({"skip": True} if p.get("skip") else {}),
                })
            profiles.sort(key=lambda p: p["iso"])
            models.append({
                "model": model["model"],
                "comment": model.get("comment", ""),
                "profiles": profiles,
            })
        models.sort(key=lambda m: m["model"])
        makers.append({"maker": maker_entry["maker"], "models": models})
    makers.sort(key=lambda m: m["maker"])
    return {"version": dt.get("version", 0), "noiseprofiles": makers}


def self_check(dt_path: str, out: dict) -> None:
    """转换前后：每 model 档数守恒 + 抽 3 model 逐值 diff（== 0 才过）。"""
    with open(dt_path, "r", encoding="utf-8") as f:
        dt = json.load(f)
    dt_models = {}
    for maker_entry in dt["noiseprofiles"]:
        for model in maker_entry["models"]:
            dt_models[(maker_entry["maker"], model["model"])] = model["profiles"]
    out_models = {}
    for maker_entry in out["noiseprofiles"]:
        for model in maker_entry["models"]:
            out_models[(maker_entry["maker"], model["model"])] = model["profiles"]
    # 1. model 集合一致 + 每 model 档数守恒
    assert set(dt_models) == set(out_models), "model 集合不一致"
    print(f"models: {len(dt_models)} 集合一致")
    for key, dt_profiles in dt_models.items():
        assert len(out_models[key]) == len(dt_profiles), f"{key} 档数 {len(dt_profiles)} != {len(out_models[key])}"
    total = sum(len(v) for v in dt_models.values())
    print(f"profiles: {total} 档数全部守恒")
    # 2. 抽 3 model 逐值 diff（首/中/尾各一）
    keys = sorted(dt_models)
    picks = [keys[0], keys[len(keys) // 2], keys[-1]]
    for key in picks:
        dt_by_iso = {p["iso"]: p for p in dt_models[key]}
        out_by_iso = {p["iso"]: p for p in out_models[key]}
        assert set(dt_by_iso) == set(out_by_iso), f"{key} ISO 集合不一致"
        worst = 0.0
        compared = 0
        for iso, dp in dt_by_iso.items():
            op = out_by_iso[iso]
            assert dp["name"] == op["name"], f"{key} iso {iso} name 不一致"
            assert dp.get("skip", False) == op.get("skip", False), f"{key} iso {iso} skip 不一致"
            for k in ("a", "b"):
                for x, y in zip(dp[k], op[k]):
                    compared += 1
                    worst = max(worst, abs(x - y))
        assert compared > 0
        assert worst == 0.0, f"{key} 逐值 diff {worst} != 0"
        print(f"diff=0: {key[0]} / {key[1]}（{len(dt_by_iso)} 档，{compared} 值）")
    # 3. 有序性：makers/models 字典序、profiles ISO 升序
    maker_names = [m["maker"] for m in out["noiseprofiles"]]
    assert maker_names == sorted(maker_names), "makers 非字典序"
    for maker_entry in out["noiseprofiles"]:
        model_names = [m["model"] for m in maker_entry["models"]]
        assert model_names == sorted(model_names), f"{maker_entry['maker']} models 非字典序"
        for model in maker_entry["models"]:
            isos = [p["iso"] for p in model["profiles"]]
            assert isos == sorted(isos), f"{model['model']} profiles 非 ISO 升序"
    print("有序性：makers/models 字典序 + profiles ISO 升序 OK")


def main() -> None:
    root = repo_root()
    dt_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DT
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        root, "LightamerIOP", "Resources", "NoiseProfiles", "noiseprofiles.json")
    out = normalize(dt_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {out_path} ({os.path.getsize(out_path)} B)")
    self_check(dt_path, out)
    print("SELF-CHECK PASS")


if __name__ == "__main__":
    main()
