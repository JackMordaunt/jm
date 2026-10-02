/*
Package shapes is the gallery's contract: a tile the ui needs, the image
that answers it, and the statistics the header shows. The ui and the
application both import this and never each other.
*/
package gallery_shapes

// Tile is one cell of the grid at a pixel size layout chose.
Tile :: struct {
	index: int,
	px:    int,
}

// Patch is one square of a tile's picture at a zoom level, for the
// viewer: level 0 is the whole picture, level n splits it 2^n ways each
// way, and x, y say which square. Answered with a Tile_Result too.
Patch :: struct {
	index, level, x, y, px: int,
}

// Tile_Result answers Tile and Patch: an image file the renderer reads
// by path.
Tile_Result :: struct {
	path: string,
}

// Stats is what the application has done so far.
Stats :: struct {}

Stats_Result :: struct {
	open:        int, // picture streams the ui holds open: needs live now
	generated:   int, // pictures drawn to completion
	cancelled:   int, // pictures abandoned because the ui stopped needing them
	pending:     int, // pictures being made now
	cached:      int, // pictures in the cache
	cache_bytes: int, // what they take, against the cache's budget
	hits:        int, // streams answered from the cache
	misses:      int, // streams that had to make their picture
	evictions:   int, // pictures the cache let go
}
