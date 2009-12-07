Rem
Copyright (c) 2009 Noel R. Cower

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EndRem

SuperStrict

Module Cower.GLMax2D

Import Brl.LinkedList
Import Brl.GLGraphics
Import Pub.Glew

Private

Function FloatsDiffer:Int(a:Float, b:Float) NoDebug
	Const FLOAT_EPSILON:Float = 5.96e-08
	Return Abs(a-b) > FLOAT_EPSILON
End Function

Type TRenderIndices
	Field indexFrom:Int = 0
	Field indices:Int = 0
	Field numIndices:Int = 0
	
	Method Clone:TRenderIndices()
		Local c:TRenderIndices = New TRenderIndices
		MemCopy(Varptr c.indexFrom, Varptr indexFrom, SizeOf(TRenderState))
		Return c
	End Method
End Type

Type TRenderState
	Field textureName:Int = 0	' may be zero
	
	Field renderMode:Int = GL_POLYGON' GL_POLYGON, etc.
	
	Field blendSource:Int = GL_ONE
	Field blendDest:Int = GL_ZERO
	
	Field alphaFunc:Int = GL_ALWAYS
	Field alphaRef:Float = 0 'GLclampf
	
	Method Bind()
		If _current = Self Then
			Return
		EndIf
		
		If Not _current Or textureName <> _current.textureName Then
			If textureName = 0 And _texture2DEnabled Then
				glDisable(GL_TEXTURE_2D)
				_texture2DEnabled = False
			Else
				If Not _texture2DEnabled Then
					glEnable(GL_TEXTURE_2D)
					_texture2DEnabled = True
				EndIf
				glBindTexture(GL_TEXTURE_2D, textureName)
			EndIf
		EndIf
		
		If Not _current Or blendDest <> _current.blendDest Or blendSource <> _current.blendSource Then
			If blendDest = GL_ONE And blendDest = GL_ZERO And _blendEnabled Then
				glDisable(GL_BLEND)
				_blendEnabled = False
			Else
				If Not _blendEnabled Then
					glEnable(GL_BLEND)
					_blendEnabled = True
				EndIf
				glBlendFunc(blendSource, blendDest)
			EndIf
		EndIf
		
		If Not _current Or alphaFunc <> _current.alphaFunc Or FloatsDiffer(alphaRef, _current.alphaRef) Then
			If alphaFunc = GL_ALWAYS And _alphaTestEnabled Then
				glDisable(GL_ALPHA_TEST)
				_alphaTestEnabled = False
			Else
				If Not _alphaTestEnabled Then
					glEnable(GL_ALPHA_TEST)
					_alphaTestEnabled = True
				EndIf
				glAlphaFunc(alphaFunc, alphaRef)
			EndIf
		EndIf
		
		_current = Self
	End Method
	
	Method Restore()
		RestoreState(Self)
	End Method
	
	Method Clone:TRenderState()
		Local c:TRenderState = New TRenderState
		MemCopy(Varptr c.textureName, Varptr textureName, SizeOf(TRenderState))
		Return c
	End Method
	
	Global _current:TRenderState
	Global _texture2DEnabled:Int = False
	Global _blendEnabled:Int = False
	Global _alphaTestEnabled:Int = False
	
	Function RestoreState(state:TRenderState=Null)
		Global _ed(cap%)[] = [glDisable, glEnable] ' this is evil
		
		If state = Null Then
			state = _current
		EndIf
		_current = Null
		Assert state Else "Cannot restore to a null state"
		
		state.Bind()
		
		' this is also evil
		_ed[_alphaTestEnabled]	GL_ALPHA_TEST
		_ed[_blendEnabled]		GL_BLEND
		_ed[_texture2DEnabled]	GL_TEXTURE_2D
	End Function
End Type

Type TRenderBuffer
	Const RENDER_BUFFER_SIZE_BYTES:Int = 131072 '128kb
 
	Field _vertbuffer:TBank, _vertstream:TBankStream
	Field _texcoordbuffer:TBank, _texcoordstream:TBankStream
	Field _colorbuffer:TBank, _colorstream:TBankStream
	Field _index:Int = 0, _sets%=0
	Field _cr@=255,_cg@=255,_cb@=255,_ca@=255
	Field _arrindices:Int[], _arrcounts:Int[]
	Field _lock%=0
	
	Field _renderIndexStack:TList
	Field _indexTop:TRenderIndices
	
	Field _renderStateStack:TList
	Field _stateTop:TRenderState
 
	Method New()
		_vertbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_vertstream = TBankStream.Create(_vertbuffer)
		
		_texcoordbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_texcoordstream = TBankStream.Create(_texcoordbuffer)
		
		_colorbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_colorstream = TBankStream.Create(_colorbuffer)
		
		_arrindices = New Int[512]
		_arrcounts = New Int[512]
		
		_stateTop = New TRenderState
		_renderStateStack = New TList
		_renderStateStack.AddLast(_stateTop)
	End Method
	
	' Add a new state/index 
	Method _newState()
		If _indexTop.indices Then
			_indexTop = _indexTop.Clone()
			_indexTop.indexFrom :+ _indexTop.indices
			_indexTop.indices = 0
			_indexTop.numIndices = 0
			_renderIndexStack.AddLast(_indexTop)
			
			_stateTop = _stateTop.Clone()
			_renderStateStack.AddLast(_stateTop)
		EndIf
	End Method
	
	Method SetTexture(tex:Int)
		If _stateTop.textureName <> tex Then
			_newState()
			_stateTop.textureName = tex
		EndIf
	End Method
	
	Method SetMode(mode:Int)
		If _stateTop.renderMode <> mode Then
			_newState()
			_stateTop.renderMode = mode
		EndIf
	End Method
	
	Method SetBlendFunc(sfac:Int, dfac:Int)
		If _stateTop.blendSource <> sfac Or _stateTop.blendDest <> dfac Then
			_newState()
			_stateTop.blendSource = sfac
			_stateTop.blendDest = dfac
		EndIf
	End Method
	
	Method SetAlphaFunc(func:Int, ref:Float)
		If _stateTop.alphaFunc <> func Or FloatsDiffer(_stateTop.alphaRef, ref) Then
			_newState()
			_stateTop.alphaFunc = func
			_stateTop.alphaRef = ref
		EndIf
	End Method
 
	Method AddPolygonEx(points:Double[], texcoords:Double[], colors:Byte[])
		Assert _lock=0 Else "Buffers are locked for rendering"
		Assert colors.Length/4 = points.Length/2 And points.Length/2 = texcoords.Length/2 And ..
			(points.Length Mod 2 = 0 And texcoords.Length Mod 2 = 0 And colors.Length Mod 4 = 0) ..
			Else "Incorrect buffer sizes"
 
		If _sets >= _arrindices.Length Then
			_arrindices = _arrindices[.. _arrindices.Length*2]
			_arrcounts = _arrcounts[.. _arrcounts.Length*2]
		EndIf
 
		Local numIndices:Int = points.Length/2
		
		_arrindices[_sets] = _index
		_arrcounts[_sets] = numIndices
 
		_texcoordstream.WriteBytes(texcoords, texcoords.Length*8)
		_vertstream.WriteBytes(points, points.Length*8)
		_colorstream.WriteBytes(colors, colors.Length)
		
		_sets :+ 1
		_indexTop.indices :+ 1
		
		_index :+ numIndices
		_indexTop.numIndices :+ numIndices
	End Method
 
	Method AddRectangle(x!, y!, z!, w!, h!, u0!=0, v0!=0, u1!=1, v1!=1)
		Local udif!=u1-u0
		Local vdif!=v1-v0
		AddPolygonEx([x,y,z, x+w,y,z, x+w,y+h,z, x,y+h,z], ..
			[u0,v0,u0+udif,v0,u0+udif,v0+vdif,u0,v0+vdif], ..
			[_cr,_cg,_cb,_ca,_cr,_cg,_cb,_ca,_cr,_cg,_cb,_ca,_cr,_cg,_cb,_ca])
	End Method
 
	Method SetAutoColor(r%,g%,b%,a%)
		_cr=r&$FF
		_cg=g&$FF
		_cb=b&$FF
		_ca=a&$FF
	End Method
 
	Method GetAutoColor(r% Var, g% Var, b% Var, a% Var)
		r = _cr
		g = _cg
		b = _cb
		a = _ca
	End Method
 
	Method LockBuffers()
		If _lock = 0 Then
			glVertexPointer(3, GL_DOUBLE, 0, _vertbuffer.Lock())
			glColorPointer(4, GL_UNSIGNED_BYTE, 0, _colorbuffer.Lock())
			glTexCoordPointer(2, GL_DOUBLE, 0, _texcoordbuffer.Lock())
		EndIf
		_lock :+ 1
	End Method
 
	Method UnlockBuffers()
		Assert _lock > 0 Else "Unmatched unlock for buffers"
		_lock :- 1
		If _lock = 0 Then
			glVertexPointer(4, GL_FLOAT, 0, Null)
			glColorPointer(4, GL_FLOAT, 0, Null)
			glTexCoordPointer(4, GL_FLOAT, 0, Null)
			_vertbuffer.Unlock()
			_colorbuffer.Unlock()
			_texcoordbuffer.Unlock()
		EndIf
	End Method
 
	Method Render()
		LockBuffers ' because we don't want to be robbed
		
		Local indexPointer%Ptr, countPointer%Ptr
		Local indexEnum:TListEnum, stateEnum:TListEnum
		
		' there's probably a better way to do this.  Like having another type that contains both the state and indices.  Or something.
		indexEnum = _renderIndexStack.ObjectEnumerator()
		stateEnum = _renderStateStack.ObjectEnumerator()
		While indexEnum.HasNext() And stateEnum.HasNext()
			Local state:TRenderState = TRenderState(stateEnum.NextObject())
			Local index:TRenderIndices = TRenderIndices(indexEnum.NextObject())
			
			If index.indices = 0 Then
				Continue
			EndIf
			
			state.Bind()
			
			glMultiDrawArrays(state.renderMode, Varptr _arrindices[index.indexFrom], Varptr _arrcounts[index.indexFrom], index.indices)
		Wend
		
		_stateTop = New TRenderState
		_renderStateStack.Clear()
		_renderStateStack.AddLast(_stateTop)
		UnlockBuffers ' but sometimes we think we're safe
	End Method
 
	Method ResetBuffers()
		' make like nothing happened and equip a wig of charisma
		Assert _lock = 0 Else "Buffers are locked for rendering"
		_vertstream.Seek(0)
		_texcoordstream.Seek(0)
		_colorstream.Seek(0)
		_index = 0
		_sets = 0
	End Method
End Type

' TODO: driver
