#
# @author Andrey Kaipov
#
# This class represents a mesh constructed of half-edges, and is initialized from a simple list
# of vertices and a list of faces indexed onthose vertices. Once initialized, we can build it,
# orient it, find its boundaries, and compute some topological and geometrical properties of it.
#

require_relative "HalfEdge"
require_relative "HalfEdgeVertex"
require_relative "HalfEdgeFace"
require_relative "HalfEdgeHash"

require "set"

class HalfEdgeMesh

    attr_reader :mesh, :hevertices, :hefaces, :hehash, :disconnectedGroups

    # Many attributes here can exist as methods, but I think it's pretty nice to initialize all of them here.
    def initialize mesh

        @mesh = mesh
        @heVertices = []
        @heFaces = []
        @heEdges = []

        self.build
        self.orient_and_find_disconnected_groups
        
    end

    def from_list_of_faces disconnectedGroup

        @heFaces = disconnectedGroup
        @heEdges = disconnectedGroup.flat_map { |hef| hef.adj_half_edges }
        @heVertices = Set.new( @heEdges.map { |he| he.endVertex } ).to_a

    end

    # Builds the simple mesh as a half-edge data structure.
    def build
        build_vertices
        build_faces
    end

    # Transforms our simple vertices into half-edge vertices.
    def build_vertices
        @mesh.vertices.each do |v|
            @heVertices << HalfEdgeVertex.new(v[0], v[1], v[2])
        end
    end

    # Transforms our faces into half-edge faces, and create the links between half-edges around each face.
    # The orientation we give each face is arbitrary -- we'll fix it later if necessary.
    def build_faces
        heHash = HalfEdgeHash.new()

        @mesh.faces.each do |face|
            halfEdgeFace = HalfEdgeFace.new()
            halfEdgeFace.oriented = false

            # For each vertex of our face, there is a corresponding half-edge.
            faceHalfEdges = face.map do |_|
                halfEdge = HalfEdge.new()
                halfEdge.adjFace = halfEdgeFace
                halfEdge
            end

            # Set the face to touch one of its half-edges. Doesn't matter which one.
            halfEdgeFace.adjHalfEdge = faceHalfEdges[0]

            # For each half-edge, connect it to the next one, and set the opposite of it via hashing.
            # Also populate the half-edges array.
            faceHalfEdges.size.times do |i|
                faceHalfEdges[i].endVertex = @heVertices[ face[i] ]
                faceHalfEdges[i - 1].nextHalfEdge = faceHalfEdges[i]
                @heVertices[ face[i - 1] ].outHalfEdge = faceHalfEdges[i]

                key = heHash.form_edge_key face[i - 1], face[i]
                heHash.hash_edge key, faceHalfEdges[i]

                @heEdges << faceHalfEdges[i]
            end

            @heFaces << halfEdgeFace
        end
    end

    # Iteratively orient all of the faces in our mesh.
    def orient_and_find_disconnected_groups

        unorientedFaces = @heFaces
        @disconnectedGroups = []

        until unorientedFaces.empty? do

            startingFace = unorientedFaces[0]
            startingFace.oriented = true

            orientedFaces = []
            orientedFaces << startingFace

            group = []

            until orientedFaces.empty? do
                face = orientedFaces.pop
                adjOrientedFaces = face.orient_adj_faces
                adjOrientedFaces.each{ |face| orientedFaces << face }

                # Before looping again, add the face into the group.
                group << face
            end

            @disconnectedGroups << group

            unorientedFaces = unorientedFaces.select{ |face| not face.oriented? }

        end

        return true

    end

    def all_faces_oriented
        @heFaces.each do |hef|
            if not hef.oriented? then
                return false
            end
        end
        return true;
    end

    def vertices
        # if @heVertices.size != @mesh.vertices.size then
        #     abort "Not every vertex from the obj file was made into a half-edge-vertex."
        # else
            return @heVertices.size
        # end
    end

    def faces
        # if @heFaces.size != @mesh.faces.size then
        #     abort "Not every face from the obj file was made into a half-edge-face."
        # else
            return @heFaces.size
        # end
    end

    def edges
        boundaryEdges = []
        nonboundaryHEs = []
        @heEdges.each do |he|
            if he.is_boundary_edge? then
                boundaryEdges << he
            else
                nonboundaryHEs << he
            end
        end
        return boundaryEdges.size + nonboundaryHEs.size / 2
    end

    def boundary_vertices
        @heVertices.select{ |v| v.is_boundary_vertex? }.size
    end

    def boundary_edges
        @heEdges.select{ |he| he.is_boundary_edge? }.size
    end

    # DFS on the boundary vertices.
    def boundaries
        boundaryVertices = @heVertices.select{ |v| v.is_boundary_vertex? }
        boundaryComponents = []
        until boundaryVertices.empty? do
            boundaryComponent = []
            discovered = [ boundaryVertices.shift ]
            until discovered.empty? do
                v = discovered.pop
                boundaryComponent << v
                boundaryVertices.each do |bv|
                    if v.adjacent_via_boundary_edge_to? bv then discovered << bv end
                end
                boundaryVertices = boundaryVertices - discovered
            end
            boundaryComponents << boundaryComponent
        end
        return boundaryComponents
    end

    def is_closed?
        boundary_edges == 0
    end

    def curvature
        @heVertices.map(&:compute_curvature).reduce(0, &:+)
    end

    def characteristic
        vertices - edges + faces
    end

    def genus
        1 - (characteristic + boundaries.size) / 2
    end

    def print_info

        if @disconnectedGroups.size == 1 then

            puts "Here is some information about the surface:"
            self.print_info_for_mesh

        else

            puts "This obj file has #{@disconnectedGroups.size} disconnected mesh groups!"
            puts "It seems like that traversing our faces via adjacency queries did not touch every face!"
            puts "However, here is the information for each mesh group separately."

            @disconnectedGroups.each_with_index do |meshGroup, i|
                puts ""
                printf "====================================\n"
                printf "========== Mesh Group %2d ===========\n", (i + 1)
                printf "====================================\n"
                self.from_list_of_faces meshGroup
                self.print_info_for_mesh
            end

        end

    end

    def print_info_for_mesh
        if boundary_vertices < boundary_edges then
            abort "The number of boundary vertices is less than the number of boundary edges.\n"\
            "This could mean that you have a non-manifold boundary vertex in your mesh. Picture a bow-tie."
        elsif boundary_vertices > boundary_edges then
            abort "Lol something went really wrong."
        end

        puts ""
        puts "Number of vertices............. V = #{vertices}"
        puts "Number of edges................ E = #{edges}"
        puts "Number of faces................ F = #{faces}"
        puts ""
        if self.is_closed? then
            puts "Surface is closed. No boundaries!"
        else
            puts "Surface is not closed and has boundaries."
            puts ""
            puts "Number of boundaries........... b = #{boundaries.size}"
            puts "- boundary vertices............ #{boundary_vertices}"
            puts "- boundary edges............... #{boundary_edges}"
        end
        puts ""
        puts "Euler characteristic........... χ = #{characteristic}"
        puts "Genus.......................... g = #{genus}"
        puts "Curvature of surface........... κ = #{curvature}"
        puts "Check Gauss-Bonnet..... |κ - 2πχ| = #{(curvature - 2 * Math::PI * characteristic).abs}"
    end

end
