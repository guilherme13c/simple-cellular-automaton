__kernel void update(__global const uint* in, __global uint* out, uint width, uint height) {
    int gid = get_global_id(0);
    int x = gid % width;
    int y = gid / width;

    if (x >= width || y >= height) return;

    int count = 0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            int nx = x + dx;
            int ny = y + dy;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                count += in[ny * width + nx];
            }
        }
    }

    int index = y * width + x;
    uint cell = in[index];
    if (cell == 1) {
        out[index] = (count == 2 || count == 3) ? 1 : 0;
    } else {
        out[index] = (count == 3) ? 1 : 0;
    }
}
