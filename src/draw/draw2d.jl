#
# This file is a part of MolecularGraph.jl
# Licensed under the MIT License http://opensource.org/licenses/MIT
#

export
    DRAW_SETTING,
    atomcolor, isatomvisible, coords2d, bondnotation,
    chargesign, atommarkup, atomhtml,
    draw2d!, drawatomindex!


"""
    DRAW_SETTING

Default setting parameters of the molecule drawing canvas.

# Required fields

- `:display_terminal_carbon`(Bool) whether to display terminal C atom or not
- `:double_bond_notation`(Symbol)
    - `:alongside`: all double bonds are represented as a carbon skeleton and
                    a segment alongside it.
    - `:dual`: all double bonds are represented as two equal length parallel
               segments.
    - `:chain`: `:dual` for chain bonds and `:alongside` for ring bonds
    - `:terminal`: `:dual` for terminal bonds (adjacent to degree=1 node) and
                   `:alongside` for others (default)
- `:atomcolor`(Dict{Symbol,Color}) atom symbol and bond colors for organic atoms
- `:defaul_atom_color`(Dict{Symbol,Color}) colors for other atoms
"""
const DRAW_SETTING = Dict(
    :display_terminal_carbon => false,
    :double_bond_notation => :terminal,  # :alongside, :dual, :chain, :terminal
    :atomcolor => Dict(
        :H => Color(0, 0, 0),
        :B => Color(128, 0, 0),
        :C => Color(0, 0, 0),
        :N => Color(0, 0, 255),
        :O => Color(255, 0, 0),
        :F => Color(0, 255, 0),
        :Si => Color(128, 64, 192),
        :P => Color(192, 0, 192),
        :S => Color(192, 192, 0),
        :Cl => Color(64, 192, 64),
        :As => Color(128, 0, 128),
        :Se => Color(128, 128, 0),
        :Br => Color(0, 192, 0),
        :I => Color(0, 128, 0)
    ),
    :default_atom_color => Color(0, 192, 192)
)


"""
    atomcolor(mol::GraphMol; setting=DRAW_SETTING)

Return atom colors for molecule 2D drawing
"""
function atomcolor(mol::GraphMol; setting=DRAW_SETTING)
    atomc = setting[:atomcolor]
    dfc =  setting[:default_atom_color]
    return [get(atomc, sym, dfc) for sym in atomsymbol(mol)]
end


function isatomvisible(mol::GraphMol; setting=DRAW_SETTING)
    termc = setting[:display_terminal_carbon]
    vec = Bool[]
    for (deg, sym) in zip(nodedegree(mol), atomsymbol(mol))
        isvisible = deg == 0 || sym != :C || (termc && deg == 1)
        push!(vec, isvisible)
    end
    return vec
end


@cache function coords2d(mol::GraphMol; recalculate=false)
    recalculate && return compute2dcoords(mol)
    nodetype(mol) === SmilesAtom && return compute2dcoords(mol)
    matrix = zeros(Float64, nodecount(mol), 2)
    for (i, node) in nodesiter(mol)
        matrix[i, :] = node.coords[1:2]
    end
    return cartesian2d(matrix)
end


function bondnotation(mol::GraphMol; setting=DRAW_SETTING)
    if nodetype(mol) === SDFileAtom
        notation = getproperty.(edgevalues(mol), :notation)
    else
        notation = zeros(Int, edgecount(mol))
    end
    dbnt = setting[:double_bond_notation]
    bondorder_ = bondorder(mol)
    # All double bonds to be "="
    if dbnt == :dual
        for b in findall(bondorder_ .== 2)
            notation[b] = 2
        end
        return
    end

    # Or only non-ring bonds to be "="
    if dbnt == :terminal
        for i in findall(nodedegree(mol) .== 1)
            b = pop!(incidences(mol, i))
            if bondorder_[b] == 2
                notation[b] = 2
            end
        end
    elseif dbnt == :chain
        for b in findall(.!bond_isringmem(mol) .* (bondorder_ .== 2))
            notation[b] = 2
        end
    end

    # Align double bonds alongside the ring
    for ring in sort(sssr(mol), by=length, rev=true)
        cw = isclockwise(cyclicpath(coords2d(mol), ring))
        cw === nothing && continue
        succ = Dict()
        ordered = cw ? ring : reverse(ring)
        for n in 1:length(ring)-1
            succ[ordered[n]] = ordered[n+1]
        end
        succ[ordered[end]] = ordered[1]
        rsub = nodesubgraph(mol.graph, ring)
        for (i, e) in edgesiter(rsub)
            if bondorder_[i] == 2 && succ[e.u] != e.v
                notation[i] = 1
            end
        end
    end
    return notation
end


"""
    chargesign(charge::Int) -> String

Get a charge sign.
"""
function chargesign(charge::Int)
    charge == 0 && return ""
    sign = charge > 0 ? "+" : "–" # en dash, not hyphen-minus
    num = abs(charge)
    return num > 1 ? string(num, sign) : sign
end


function atommarkup(symbol, charge, hcount, direction,
                    substart, subend, supstart, supend)
    if hcount == 1
        hs = "H"
    elseif hcount > 1
        hs = string("H", substart, hcount, subend)
    else
        hs = ""
    end
    chg = charge == 0 ? "" : string(supstart, chargesign(charge), supend)
    txt = direction == :left ? [chg, hs, symbol] : [symbol, hs, chg]
    return string(txt...)
end


atomhtml(
    symbol, charge, hcount, direction
) = atommarkup(
    symbol, charge, hcount, direction, "<sub>", "</sub>", "<sup>", "</sup>")


"""
    draw2d!(canvas::Canvas, mol::GraphMol;
            setting=copy(DRAW_SETTING), recalculate=false)

Draw molecular image to the canvas.
"""
function draw2d!(canvas::Canvas, mol::GraphMol;
                 setting=copy(DRAW_SETTING), recalculate=false)
    # Canvas settings
    initcanvas!(canvas, mol)
    canvas.valid || return

    # Properties
    atomsymbol_ = atomsymbol(mol)
    atomcolor_ = atomcolor(mol)
    charge_ = charge(mol)
    isatomvisible_ = isatomvisible(mol)
    bondorder_ = bondorder(mol)
    bondnotation_ = bondnotation(mol)
    implicithcount_ = implicithcount(mol)

    # Draw bonds
    for (i, bond) in edgesiter(mol)
        setbond!(
            canvas, bondorder_[i], bondnotation_[i],
            segment(canvas.coords, bond.u, bond.v),
            atomcolor_[bond.u], atomcolor_[bond.v],
            isatomvisible_[bond.u], isatomvisible_[bond.v]
        )
    end

    # Draw atoms
    for i in 1:atomcount(mol)
        isatomvisible_[i] || continue
        pos = _point(canvas.coords, i)
        # Determine text direction
        if implicithcount_[i] > 0
            cosnbrs = []
            hrzn = [pos[1] + 1.0, pos[2]]
            for nbr in adjacencies(mol, i)
                posnbr = _point(canvas.coords, nbr)
                dist = norm(posnbr - pos)
                if dist > 0
                    dp = dot(hrzn - pos, posnbr - pos)
                    push!(cosnbrs, dp / dist)
                end
            end
            if isempty(cosnbrs) || minimum(cosnbrs) > 0
                # [atom]< or isolated node(ex. H2O, HCl)
                setatomright!(
                    canvas, pos, atomsymbol_[i], atomcolor_[i],
                    implicithcount_[i], charge_[i]
                )
                continue
            elseif maximum(cosnbrs) < 0
                # >[atom]
                setatomleft!(
                    canvas, pos, atomsymbol_[i], atomcolor_[i],
                    implicithcount_[i], charge_[i]
                )
                continue
            end
        end
        # -[atom]- or no hydrogens
        setatomcenter!(
            canvas, pos, atomsymbol_[i], atomcolor_[i],
            implicithcount_[i], charge_[i]
        )
    end
    return
end


function drawatomindex!(canvas::Canvas, mol::GraphMol;
                        color=Color(0, 0, 0), bgcolor=Color(240, 240, 255))
    isatomvisible_ = isatomvisible(mol)
    for i in 1:atomcount(mol)
        offset = isatomvisible_[i] ? [0 canvas.fontsize/2] : [0 0]
        pos = _point(canvas.coords, i) + offset
        setatomnote!(canvas, pos, string(i), color, bgcolor)
    end
    return
end
