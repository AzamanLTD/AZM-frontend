local SEGMENTS = 32
local IMAGE_SIZE = 512

type Liquid = {
    mark: Image?,
    redFringe: Image?,
    cyanFringe: Image?,
    vertices: VertexBuffer,
    markUvs: VertexBuffer,
    redUvs: VertexBuffer,
    cyanUvs: VertexBuffer,
    triangles: TriangleBuffer,
    sampler: ImageSampler,
    elapsed: number,
}

local function init(self: Liquid, context: Context): boolean
    self.mark = context:image("azaman-mark")
    self.redFringe = context:image("azaman-mark-red")
    self.cyanFringe = context:image("azaman-mark-cyan")
    self.vertices = VertexBuffer()
    self.markUvs = VertexBuffer()
    self.redUvs = VertexBuffer()
    self.cyanUvs = VertexBuffer()
    self.triangles = TriangleBuffer()
    self.sampler = ImageSampler("clamp", "clamp", "bilinear")

    local rowLength = SEGMENTS + 1
    for y = 0, SEGMENTS do
        for x = 0, SEGMENTS do
            local u = x / SEGMENTS
            local v = y / SEGMENTS
            self.markUvs:add(Vector.xy(u, v))
            self.redUvs:add(Vector.xy(u, v))
            self.cyanUvs:add(Vector.xy(u, v))
        end
    end

    for y = 0, SEGMENTS - 1 do
        for x = 0, SEGMENTS - 1 do
            local a = y * rowLength + x + 1
            local b = a + 1
            local c = a + rowLength
            local d = c + 1
            self.triangles:add(a, c, b)
            self.triangles:add(b, c, d)
        end
    end
    return true
end

local function smoothstep(edge0: number, edge1: number, value: number): number
    local t = math.clamp((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
end

local function advance(self: Liquid, seconds: number): boolean
    self.elapsed = (self.elapsed + seconds) % 3.0
    return true
end

local function draw(self: Liquid, renderer: Renderer)
    local mark = self.mark
    local redFringe = self.redFringe
    local cyanFringe = self.cyanFringe
    if not mark or mark.width == 0 or not redFringe or not cyanFringe then
        return
    end

    local time = self.elapsed
    local arrival = math.exp(-math.pow((time - 0.42) / 0.38, 2))
    local departure = math.exp(-math.pow((time - 2.42) / 0.4, 2))
    local refraction = math.max(arrival, departure)
    local strength = 0.009 + refraction * 0.115
    local colorOffset = 0.006 + refraction * 0.026
    local reveal = smoothstep(0.04, 0.38, time)
    local dissolve = 1 - smoothstep(2.66, 2.98, time)
    local opacity = reveal * dissolve

    self.vertices:reset()
    self.markUvs:reset()
    self.redUvs:reset()
    self.cyanUvs:reset()

    for y = 0, SEGMENTS do
        for x = 0, SEGMENTS do
            local u = x / SEGMENTS
            local v = y / SEGMENTS
            local dx = u - 0.5
            local dy = v - 0.5
            local radius = math.sqrt(dx * dx + dy * dy)
            local nx = dx / math.max(radius, 0.001)
            local ny = dy / math.max(radius, 0.001)
            local wave = math.sin(radius * 31 - time * 7.4) * math.exp(-radius * 2.2)
                + 0.5 * math.sin(radius * 58 - time * 9.2) * math.exp(-radius * 3.8)
            local swirl = math.sin(radius * 15 - time * 3.8 + dy * 7) * math.exp(-radius * 2.6)
            local crossFlow = math.sin(u * 12 + v * 8 - time * 5.5) * math.exp(-radius * 1.3)
            local shiftX = nx * wave * strength - ny * swirl * strength * 0.58 + crossFlow * strength * 0.2
            local shiftY = ny * wave * strength + nx * swirl * strength * 0.58 + crossFlow * strength * 0.13
            local warpedU = math.clamp(u + shiftX, 0.002, 0.998)
            local warpedV = math.clamp(v + shiftY, 0.002, 0.998)

            self.vertices:add(Vector.xy(u * IMAGE_SIZE, v * IMAGE_SIZE))
            self.markUvs:add(Vector.xy(warpedU, warpedV))
            self.redUvs:add(Vector.xy(math.clamp(warpedU - colorOffset, 0.002, 0.998), warpedV))
            self.cyanUvs:add(Vector.xy(math.clamp(warpedU + colorOffset, 0.002, 0.998), warpedV))
        end
    end

    renderer:drawImageMesh(redFringe, self.sampler, self.vertices, self.redUvs, self.triangles, "srcOver", opacity * refraction * 0.7)
    renderer:drawImageMesh(cyanFringe, self.sampler, self.vertices, self.cyanUvs, self.triangles, "srcOver", opacity * refraction * 0.7)
    renderer:drawImageMesh(mark, self.sampler, self.vertices, self.markUvs, self.triangles, "srcOver", opacity)
end

return function(): Node<Liquid>
    return {
        mark = nil,
        redFringe = nil,
        cyanFringe = nil,
        vertices = VertexBuffer(),
        markUvs = VertexBuffer(),
        redUvs = VertexBuffer(),
        cyanUvs = VertexBuffer(),
        triangles = TriangleBuffer(),
        sampler = ImageSampler("clamp", "clamp", "bilinear"),
        elapsed = 0,
        init = init,
        advance = advance,
        draw = draw,
    }
end
