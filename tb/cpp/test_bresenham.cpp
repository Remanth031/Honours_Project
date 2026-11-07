#include <iostream>
#include <vector>
#include <cstdint>
#include <cassert>

using namespace std;

struct Pixel { int x, y; };

vector<Pixel> bresenham(int x0, int y0, int x1, int y1) {
    vector<Pixel> pts;
    int raw_dx = x1 - x0;
    int raw_dy = y1 - y0;
    int dx = (raw_dx < 0) ? -raw_dx : raw_dx;
    int dy = (raw_dy < 0) ? -raw_dy : raw_dy;
    bool sx = (raw_dx >= 0);
    bool sy = (raw_dy >= 0);
    bool steep = (dy > dx);
    int err = steep ? (2 * dx - dy) : (2 * dy - dx);

    int cx = x0;
    int cy = y0;

    while (true) {
        pts.push_back({cx, cy});
        if (cx == x1 && cy == y1) break;

        if (!steep) {
            cx += (sx ? 1 : -1);
            if (err >= 0) {
                cy += (sy ? 1 : -1);
                err += 2 * dy - 2 * dx;
            } else {
                err += 2 * dy;
            }
        } else {
            cy += (sy ? 1 : -1);
            if (err >= 0) {
                cx += (sx ? 1 : -1);
                err += 2 * dx - 2 * dy;
            } else {
                err += 2 * dx;
            }
        }
    }
    return pts;
}

int main() {
    auto p1 = bresenham(10, 22, 11, 22);
    cout << "H-line (10,22)->(11,22): " << p1.size() << " pixels\n";
    for (auto p : p1) cout << "  (" << p.x << "," << p.y << ")\n";

    auto p2 = bresenham(10, 20, 10, 25);
    cout << "V-line (10,20)->(10,25): " << p2.size() << " pixels\n";

    auto p3 = bresenham(0, 0, 5, 5);
    cout << "Diag (0,0)->(5,5): " << p3.size() << " pixels\n";

    auto p4 = bresenham(100, 100, 100, 100);
    cout << "Point (100,100): " << p4.size() << " pixels\n";

    return 0;
}
