######################################################################
# GenerateProperties UTs
# -----
# Licensed under MIT License
using Test
using GenerateProperties

function noop(args...; kwargs...) end

@testset "GenerateProperties" begin
    @testset "flat" begin
        mutable struct TestFlatStruct
            size::NTuple{2, Float32}
        end
        TestFlatStruct() = TestFlatStruct((0, 0))
        
        @generate_properties TestFlatStruct begin
            @get width = self.size[1]
            @set width = self.size = (value, self.size[2])
            @get height = self.size[2]
            @set height = self.size = (self.size[1], value)
        end
        
        let inst = TestFlatStruct()
            @test inst.size == (0, 0) && inst.width == 0 && inst.height == 0
            
            @test (inst.width = 69) == 69 && (inst.height = 420) == 420
            @test inst.size == (69, 420) && inst.width == 69 && inst.height == 420
            
            @test (inst.size = (24, 25)) == (24, 25)
            @test inst.size == (24, 25) && inst.width == 24 && inst.height == 25
        end
    end
    
    @testset "nested" begin
        mutable struct SizeSimple
            width::Float64
            height::Float64
        end
        
        mutable struct TestNestedStruct
            size::SizeSimple
        end
        TestNestedStruct() = TestNestedStruct(SizeSimple(0, 0))
        
        @generate_properties TestNestedStruct begin
            @get width = self.size.width
            @set width = self.size.width = value
            @get height = self.size.height
            @set height = self.size.height = value
            @get size = (self.size.width, self.size.height)
            @set size = self.size = SizeSimple(value[1], value[2])
        end
        
        let inst = TestNestedStruct()
            @test inst.size == (0, 0) && inst.width == 0 && inst.height == 0
            
            @test (inst.width = 24) == 24 && (inst.height = 25) == 25
            @test inst.size == (24, 25) && inst.width == 24 && inst.height == 25
            
            @test (inst.size = (69, 69)) == (69, 69)
            @test inst.size == (69, 69) && inst.width == 69 && inst.height == 69
        end
    end
    
    @testset "complex" begin
        mutable struct TestComplexStruct
            size::NTuple{2, Int}
            dirty::Bool
            callback
        end
        TestComplexStruct(cb) = TestComplexStruct((0, 0), false, cb)
        TestComplexStruct() = TestComplexStruct((0, 0), false, noop)
        
        @generate_properties TestComplexStruct begin
            @set size = (self.dirty = true; self.callback(); self.size = value)
            
            @get width = self.size[1]
            @set width = (self.dirty = true; self.callback(); self.size = (value, self.size[2]))
            
            @get height = self.size[1]
            @set height = (self.dirty = true; self.callback(); self.size = (self.size[1], value))
        end
        
        let inst = TestComplexStruct(), callback_called = false
            @test inst.size == (0, 0) && inst.width == 0 && inst.height == 0 && !inst.dirty
            inst.callback() = callback_called = true
            
            @test (inst.width = 42) == 42
            @test inst.size == (42, 0) && inst.width == 42 && inst.dirty
            @test callback_called
        end
    end
end
