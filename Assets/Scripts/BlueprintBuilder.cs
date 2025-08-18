using UnityEngine;
using System;
using System.Collections.Generic;
using System.Linq;

[Serializable] public class Blueprint {
    public string @class;
    public bool addRigidbody;
    public float mass = 50f;
    public Part[] parts;
}
[Serializable] public class Part {
    public string name;
    public string primitive; // Cube|Sphere|Capsule|Cylinder|Plane
    public Vector3 localPosition;
    public Vector3 localScale = Vector3.one;
    public Vector3 localEuler;
    public MatSpec material;
}
[Serializable] public class MatSpec {
    public string key;
    public string colorHex; // #RRGGBB
    public float metallic = 0f;
    public float smoothness = 0.45f;
}

public static class BlueprintBuilder
{
    static readonly Dictionary<string, Material> _matCache = new Dictionary<string, Material>();

    public static GameObject Build(string rootName, Blueprint bp)
    {
        if (bp == null) return null;
        var root = new GameObject(string.IsNullOrEmpty(rootName) ? (bp.@class ?? "GeneratedRoot") : rootName);

        var created = new List<Transform>();
        if (bp.parts != null)
        {
            foreach (var p in bp.parts)
            {
                var t = CreatePart(root.transform, p);
                if (t != null) created.Add(t);
            }
        }

        AutoSnapParts(created);

        if (bp.addRigidbody)
        {
            var rb = root.GetComponent<Rigidbody>() ?? root.AddComponent<Rigidbody>();
            rb.mass = Mathf.Max(0.1f, bp.mass);
            rb.useGravity = true;
            rb.isKinematic = false;
        }

        return root;
    }

    static Transform CreatePart(Transform parent, Part p)
    {
        var prim = ParsePrimitive(p.primitive);
        var go = GameObject.CreatePrimitive(prim);
        go.name = string.IsNullOrEmpty(p.name) ? prim.ToString() : p.name;
        go.transform.SetParent(parent, false);
        go.transform.localPosition = p.localPosition;
        go.transform.localRotation = Quaternion.Euler(p.localEuler);
        go.transform.localScale = new Vector3(
            Mathf.Max(0.01f, p.localScale.x),
            Mathf.Max(0.01f, p.localScale.y),
            Mathf.Max(0.01f, p.localScale.z)
        );

        var r = go.GetComponent<Renderer>();
        if (r != null && p.material != null)
        {
            r.sharedMaterial = GetMat(
                string.IsNullOrEmpty(p.material.key) ? (p.name ?? "Part") : p.material.key,
                string.IsNullOrEmpty(p.material.colorHex) ? "#9AA7B0" : p.material.colorHex,
                p.material.metallic,
                p.material.smoothness
            );
        }
        return go.transform;
    }

    static PrimitiveType ParsePrimitive(string s)
    {
        if (string.IsNullOrEmpty(s)) return PrimitiveType.Cube;
        s = s.Trim();
        if (s.Equals("Sphere", StringComparison.OrdinalIgnoreCase)) return PrimitiveType.Sphere;
        if (s.Equals("Capsule", StringComparison.OrdinalIgnoreCase)) return PrimitiveType.Capsule;
        if (s.Equals("Cylinder", StringComparison.OrdinalIgnoreCase)) return PrimitiveType.Cylinder;
        if (s.Equals("Plane", StringComparison.OrdinalIgnoreCase)) return PrimitiveType.Plane;
        return PrimitiveType.Cube;
    }

    static Material GetMat(string key, string html, float metallic, float smoothness)
    {
        if (string.IsNullOrEmpty(key)) key = html ?? "mat";
        if (_matCache.TryGetValue(key, out var m) && m != null) return m;

        Shader sh = null;
        var rp = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline;
        if (rp == null) sh = Shader.Find("Standard");
        else
        {
            var name = rp.GetType().FullName;
            if (name.Contains("Universal")) sh = Shader.Find("Universal Render Pipeline/Lit");
            else if (name.Contains("HD"))   sh = Shader.Find("HDRP/Lit");
        }
        if (sh == null) sh = Shader.Find("Standard");
        if (sh == null) sh = Shader.Find("Universal Render Pipeline/Lit");
        if (sh == null) sh = Shader.Find("HDRP/Lit");
        if (sh == null) sh = Shader.Find("Sprites/Default");

        m = new Material(sh) { name = key };
        m.hideFlags = HideFlags.DontSave;

        if (!string.IsNullOrEmpty(html) && ColorUtility.TryParseHtmlString(html, out var c))
        {
            if (m.HasProperty("_Color"))     m.SetColor("_Color", c);
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
        }
        if (m.HasProperty("_Metallic"))   m.SetFloat("_Metallic", metallic);
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smoothness);
        if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smoothness);

        _matCache[key] = m;
        return m;
    }

    struct PartInfo
    {
        public Transform t;
        public Renderer r;
        public Bounds b;
        public float vol;
        public float yCenter;
    }

    static PartInfo Info(Transform t)
    {
        var r = t.GetComponent<Renderer>();
        Bounds b = r != null ? r.bounds : new Bounds(t.position, Vector3.one * 0.01f);
        var s = b.size;
        float vol = Mathf.Max(0.0001f, s.x*s.y*s.z);
        return new PartInfo { t=t, r=r, b=b, vol=vol, yCenter=b.center.y };
    }

    static void AutoSnapParts(IList<Transform> parts)
    {
        if (parts == null || parts.Count == 0) return;

        var anchor = parts.Select(Info).OrderBy(i => i.yCenter).First().t;
        var snapped = new HashSet<Transform> { anchor };

        const float xzAlign = 0.30f;
        const float eps = 0.01f;

        System.Action<Transform, Transform> snapTo = (aT, bT) =>
        {
            var a = Info(aT); var b = Info(bT);
            var ac = a.b.center; var bc = b.b.center;
            var ae = a.b.extents; var be = b.b.extents;

            Vector3 p = aT.position;

            if (Mathf.Abs(ac.x-bc.x) < xzAlign && Mathf.Abs(ac.z-bc.z) < xzAlign)
            {
                if (ac.y >= bc.y) p.y = b.b.max.y + ae.y + eps;
                else               p.y = b.b.min.y - ae.y - eps;
                aT.position = p; return;
            }

            float dx1 = Mathf.Abs((b.b.max.x + ae.x + eps) - p.x);
            float dx2 = Mathf.Abs((b.b.min.x - ae.x - eps) - p.x);
            float dy1 = Mathf.Abs((b.b.max.y + ae.y + eps) - p.y);
            float dy2 = Mathf.Abs((b.b.min.y - ae.y - eps) - p.y);
            float dz1 = Mathf.Abs((b.b.max.z + ae.z + eps) - p.z);
            float dz2 = Mathf.Abs((b.b.min.z - ae.z - eps) - p.z);

            float best = dx1; int axis=0; bool pos=true;
            if (dx2 < best) { best=dx2; axis=0; pos=false; }
            if (dy1 < best) { best=dy1; axis=1; pos=true;  }
            if (dy2 < best) { best=dy2; axis=1; pos=false; }
            if (dz1 < best) { best=dz1; axis=2; pos=true;  }
            if (dz2 < best) { best=dz2; axis=2; pos=false; }

            if (axis==0) p.x = pos ? (b.b.max.x + ae.x + eps) : (b.b.min.x - ae.x - eps);
            else if (axis==1) p.y = pos ? (b.b.max.y + ae.y + eps) : (b.b.min.y - ae.y - eps);
            else p.z = pos ? (b.b.max.z + ae.z + eps) : (b.b.min.z - ae.z - eps);

            aT.position = p;
        };

        var order = parts.OrderBy(t => Info(t).yCenter). ThenByDescending(t => Info(t).vol).ToList();
        foreach (var t in order)
        {
            if (snapped.Contains(t)) continue;
            Transform nearest = anchor; float best = float.MaxValue;
            var aI = Info(t);
            foreach (var s in snapped)
            {
                var sc = Info(s).b.center;
                float d = (aI.b.center - sc).sqrMagnitude;
                if (d < best) { best = d; nearest = s; }
            }
            snapTo(t, nearest);
            snapped.Add(t);
        }

        for (int pass=0; pass<2; pass++)
        {
            foreach (var aT in parts)
            foreach (var bT in parts)
            {
                if (aT==bT) continue;
                var A=Info(aT); var B=Info(bT);
                var Ae=A.b.extents; var Be=B.b.extents;
                var Ac=A.b.center;  var Bc=B.b.center;

                Vector3 move = Vector3.zero;

                float wantAX = (Ac.x>=Bc.x) ? (B.b.max.x + Ae.x + eps) : (B.b.min.x - Ae.x - eps);
                float gapX = wantAX - aT.position.x;
                float wantAY = (Ac.y>=Bc.y) ? (B.b.max.y + Ae.y + eps) : (B.b.min.y - Ae.y - eps);
                float gapY = wantAY - aT.position.y;
                float wantAZ = (Ac.z>=Bc.z) ? (B.b.max.z + Ae.z + eps) : (B.b.min.z - Ae.z - eps);
                float gapZ = wantAZ - aT.position.z;

                float adx=Mathf.Abs(gapX), ady=Mathf.Abs(gapY), adz=Mathf.Abs(gapZ);
                float minGap = Mathf.Min(adx, Mathf.Min(ady, adz));
                if (minGap < 0.06f)
                {
                    if      (minGap==adx) move.x = gapX;
                    else if (minGap==ady) move.y = gapY;
                    else                   move.z = gapZ;
                    aT.position += move;
                }
            }
        }
    }
}
