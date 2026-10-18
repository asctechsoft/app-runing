import type { TrackPoint, TrackSegment } from "@/server/validators/activity";

// I07 (phần server): GPX chỉ dựng từ GPS thật. Mỗi segment -> một <trkseg>, chỉ point accepted.
// Không nội suy/lấp khoảng trống giữa các segment (gap/pause giữ nguyên là khoảng trống).

export interface MergedTrack {
  activityId: string;
  segments: Array<TrackSegment & { points: TrackPoint[] }>;
}

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");

export function buildGpx(track: MergedTrack, meta: { name: string; type: string; startedAt: number }): string | null {
  const segs = track.segments
    .map((s) => s.points.filter((p) => p.accepted))
    .filter((pts) => pts.length > 0);
  if (segs.length === 0) return null;
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<gpx version="1.1" creator="STRIDE" xmlns="http://www.topografix.com/GPX/1/1">',
    `  <metadata><time>${new Date(meta.startedAt).toISOString()}</time></metadata>`,
    "  <trk>",
    `    <name>${esc(meta.name)}</name>`,
    `    <type>${esc(meta.type)}</type>`,
  ];
  for (const pts of segs) {
    lines.push("    <trkseg>");
    for (const p of pts) {
      const ele = p.altitudeM != null ? `<ele>${p.altitudeM.toFixed(1)}</ele>` : "";
      lines.push(
        `      <trkpt lat="${p.lat.toFixed(7)}" lon="${p.lon.toFixed(7)}">${ele}<time>${new Date(p.t).toISOString()}</time></trkpt>`,
      );
    }
    lines.push("    </trkseg>");
  }
  lines.push("  </trk>", "</gpx>", "");
  return lines.join("\n");
}
