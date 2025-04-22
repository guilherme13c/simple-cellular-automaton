kernel void update(global const bool* grid, global bool* next_grid, const int width, const int height) {
  const int x = get_global_id(0);
  const int y = get_global_id(1);
  const int idx = y * width + x;

  if (x >= width || y >= height) return;

  int count = 0;
  for (int oy = -1; oy <= 1; oy++) {
    for (int ox = -1; ox <= 1; ox++) {
      if (ox == 0 && oy == 0) continue;

      int nx = (x + ox + width) % width;
      int ny = (y + oy + height) % height;
      int nidx = ny * width + nx;
      count += grid[nidx];
    }
  }

  uchar cell = grid[idx];
  uchar new_state = (cell == 1 && (count == 2 || count == 3)) || (cell == 0 && count == 3);
  next_grid[idx] = new_state;
}

