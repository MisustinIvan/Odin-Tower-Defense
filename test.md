# Problems
- collision is going to be terrible and slow if something does not change
- pathfinding in groups sucks, mainly because of speed
    - the problem should not lie in the pathfinding alg
    - the problem is more in handling group movement
- in the future when combat is going to be implemented, there will be many issues with access to entities


# How to fix the mess
- units have to live on a grid
- the tile structs are going to contain all of the information about the things that are happening on them
    - not just a background
    - has entity info -> Unit, Building, maybe some decorations or corpses, but those can be handled separately
    - has potential effect info -> flame, frost, etc.
- when unit moves to a new tile, it instantly occupies it and interpolates position based on speed
    - that means no other units pathfinding can occupy that location while the unit moves there
    - if it wants to move through some tile but it is occupied by another unit/building/obstacle that was not there when the path was calculated, recalculate the path

# What does that require
- it would be nice to have a type like v2 but with ints instead to avoid casting when accessing world -> g2 (grid 2)
- refactor as many things that live in the world as possible to use the g2 type
- clearly separate rendering functions from world functions
- have clear mappings between the two spaces

# Things for help
- build with more warnings : `odin build . -vet-unused -vet-packages:main -vet-unused-procedures`
