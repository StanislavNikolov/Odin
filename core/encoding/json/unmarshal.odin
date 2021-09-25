package json

import "core:fmt"
import "core:mem"
import "core:math"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:runtime"

Unmarshal_Data_Error :: enum {
	Invalid_Data,
	Invalid_Parameter,
	Non_Pointer_Parameter,
	Multiple_Use_Field,
}

Unsupported_Type_Error :: struct {
	id:    typeid,
	token: Token,
}

Unmarshal_Error :: union {
	Error,
	Unmarshal_Data_Error,
	Unsupported_Type_Error,
}

unmarshal_any :: proc(data: []byte, v: any, spec := DEFAULT_SPECIFICATION, allocator := context.allocator) -> Unmarshal_Error {
	v := v
	if v == nil || v.id == nil {
		return .Invalid_Parameter
	}
	v = reflect.any_base(v)
	ti := type_info_of(v.id)
	if !reflect.is_pointer(ti) || ti.id == rawptr {
		return .Non_Pointer_Parameter
	}
	
	
	if !is_valid(data, spec, true) {
		return .Invalid_Data
	}
	p := make_parser(data, spec, true, allocator)
	
	data := any{(^rawptr)(v.data)^, ti.variant.(reflect.Type_Info_Pointer).elem.id}
	if v.data == nil {
		return .Invalid_Parameter
	}
	return unmarsal_value(&p, data)
}


unmarshal :: proc(data: []byte, ptr: ^$T, spec := DEFAULT_SPECIFICATION, allocator := context.allocator) -> Unmarshal_Error {
	return unmarshal_any(data, ptr, spec, allocator)
}

unmarshal_string :: proc(data: string, ptr: ^$T, spec := DEFAULT_SPECIFICATION, allocator := context.allocator) -> Unmarshal_Error {
	return unmarshal_any(transmute([]byte)data, ptr, spec, allocator)
}


@(private)
assign_bool :: proc(val: any, b: bool) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case bool: dst = auto_cast b
	case b8:   dst = auto_cast b
	case b16:  dst = auto_cast b
	case b32:  dst = auto_cast b
	case b64:  dst = auto_cast b
	case: return false
	}
	return true
}
@(private)
assign_int :: proc(val: any, i: $T) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case i8:      dst = auto_cast i
	case i16:     dst = auto_cast i
	case i16le:   dst = auto_cast i
	case i16be:   dst = auto_cast i
	case i32:     dst = auto_cast i
	case i32le:   dst = auto_cast i
	case i32be:   dst = auto_cast i
	case i64:     dst = auto_cast i
	case i64le:   dst = auto_cast i
	case i64be:   dst = auto_cast i
	case i128:    dst = auto_cast i
	case i128le:  dst = auto_cast i
	case i128be:  dst = auto_cast i
	case u8:      dst = auto_cast i
	case u16:     dst = auto_cast i
	case u16le:   dst = auto_cast i
	case u16be:   dst = auto_cast i
	case u32:     dst = auto_cast i
	case u32le:   dst = auto_cast i
	case u32be:   dst = auto_cast i
	case u64:     dst = auto_cast i
	case u64le:   dst = auto_cast i
	case u64be:   dst = auto_cast i
	case u128:    dst = auto_cast i
	case u128le:  dst = auto_cast i
	case u128be:  dst = auto_cast i
	case int:     dst = auto_cast i
	case uint:    dst = auto_cast i
	case uintptr: dst = auto_cast i
	case: return false
	}
	return true
}
@(private)
assign_float :: proc(val: any, i: $T) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case f16:     dst = auto_cast i
	case f16le:   dst = auto_cast i
	case f16be:   dst = auto_cast i
	case f32:     dst = auto_cast i
	case f32le:   dst = auto_cast i
	case f32be:   dst = auto_cast i
	case f64:     dst = auto_cast i
	case f64le:   dst = auto_cast i
	case f64be:   dst = auto_cast i
	case: return false
	}
	return true
}



@(private)
unmarsal_value :: proc(p: ^Parser, v: any) -> (err: Unmarshal_Error) {
	UNSUPPORTED_TYPE := Unsupported_Type_Error{v.id, p.curr_token}
	
	token := p.curr_token
	#partial switch token.kind {
	case .Null:
		ti := type_info_of(v.id)
		mem.zero(v.data, ti.size)
		advance_token(p)
		return
	case .False, .True:
		if assign_bool(v, token.kind == .True) {
			return
		}
		return UNSUPPORTED_TYPE

	case .Integer:
		advance_token(p)
		i, _ := strconv.parse_i128(token.text)
		if assign_int(v, i) {
			return
		}
		if assign_float(v, i) {
			return
		}
		return
	case .Float:
		advance_token(p)
		f, _ := strconv.parse_f64(token.text)
		if assign_float(v, f) {
			return
		}
		if i, fract := math.modf(f); fract == 0 {
			if assign_int(v, i) {
				return
			}
			if assign_float(v, i) {
				return
			}
		}
		return UNSUPPORTED_TYPE
	case .String:
		advance_token(p)
		str := unquote_string(token, p.spec, p.allocator) or_return
		val := reflect.any_base(v)
		switch dst in &val {
		case string:
			dst = str
			return
		case cstring:  
			if str == "" {
				dst = strings.clone_to_cstring("", p.allocator)
			} else {
				// NOTE: This is valid because 'clone_string' appends a NUL terminator
				dst = cstring(raw_data(str)) 
			}
			return
		}
		defer delete(str, p.allocator)
		
		ti := type_info_of(val.id)
		#partial switch variant in ti.variant {
		case reflect.Type_Info_Enum:
			for name, i in variant.names {
				if name == str {
					assign_int(val, variant.values[i])
					return nil
				}
			}
			// TODO(bill): should this be an error or not?
			return nil
			
		case reflect.Type_Info_Integer:
			i, ok := strconv.parse_i128(token.text)
			if !ok {
				return UNSUPPORTED_TYPE
			}
			if assign_int(val, i) {
				return
			}
			if assign_float(val, i) {
				return
			}
		case reflect.Type_Info_Float:
			f, ok := strconv.parse_f64(token.text)
			if !ok {
				return UNSUPPORTED_TYPE
			}
			if assign_int(val, f) {
				return
			}
			if assign_float(val, f) {
				return
			}
		}
		
		return UNSUPPORTED_TYPE


	case .Open_Brace:
		return unmarsal_object(p, v)

	case .Open_Bracket:
		return unmarsal_array(p, v)

	case:
		if p.spec == Specification.JSON5 {
			#partial switch token.kind {
			case .Infinity:
				advance_token(p)
				f: f64 = 0h7ff0000000000000
				if token.text[0] == '-' {
					f = 0hfff0000000000000
				}
				if assign_float(v, f) {
					return
				}
				return UNSUPPORTED_TYPE
			case .NaN:
				advance_token(p)
				f: f64 = 0h7ff7ffffffffffff
				if token.text[0] == '-' {
					f = 0hfff7ffffffffffff
				}
				if assign_float(v, f) {
					return
				}
				return UNSUPPORTED_TYPE
			}
		}
	}

	advance_token(p)
	return

}


@(private)
unmarsal_expect_token :: proc(p: ^Parser, kind: Token_Kind, loc := #caller_location) -> Token {
	prev := p.curr_token
	err := expect_token(p, kind)
	assert(err == nil, "unmarsal_expect_token", loc)
	return prev
}


@(private)
unmarsal_object :: proc(p: ^Parser, v: any) -> (err: Unmarshal_Error) {
	original_val := v
	UNSUPPORTED_TYPE := Unsupported_Type_Error{v.id, p.curr_token}
	
	assert(expect_token(p, .Open_Brace) == nil)

	v := v
	v = reflect.any_base(v)
	ti := type_info_of(v.id)
	
	#partial switch t in ti.variant {
	case reflect.Type_Info_Struct:
		if t.is_raw_union {
			return UNSUPPORTED_TYPE
		}
	
		struct_loop: for p.curr_token.kind != .Close_Brace {
			key, _ := parse_object_key(p, p.allocator)
			defer delete(key, p.allocator)
			
			unmarsal_expect_token(p, .Colon)						
			
			fields := reflect.struct_fields_zipped(ti.id)
			
			field_used := make([]bool, len(fields), context.temp_allocator)
			
			use_field_idx := -1
			
			for field, field_idx in fields {
				tag_value := string(reflect.struct_tag_get(field.tag, "json"))
				if key == tag_value {
					use_field_idx = field_idx
					break
				}
			}
			
			if use_field_idx < 0 {
				for field, field_idx in fields {
					if key == field.name {
						use_field_idx = field_idx
						break
					}
				}
			}
			
			if use_field_idx >= 0 {
				if field_used[use_field_idx] {
					return .Multiple_Use_Field
				}
				field_used[use_field_idx] = true
				offset := fields[use_field_idx].offset
				type := fields[use_field_idx].type
				name := fields[use_field_idx].name
				

				field_ptr := rawptr(uintptr(v.data) + offset)
				field := any{field_ptr, type.id}
				unmarsal_value(p, field) or_return
				
				if p.spec == Specification.JSON5 {
					// Allow trailing commas
					if allow_token(p, .Comma) {
						continue struct_loop
					}
				} else {
					// Disallow trailing commas
					if allow_token(p, .Comma) {
						continue struct_loop
					} else {
						break struct_loop
					}
				}
				
				continue struct_loop
			}
			
			return Unsupported_Type_Error{v.id, p.curr_token}
		}
		
	case reflect.Type_Info_Map:
		if !reflect.is_string(t.key) {
			return UNSUPPORTED_TYPE
		}
		raw_map := (^mem.Raw_Map)(v.data)
		if raw_map.entries.allocator.procedure == nil {
			raw_map.entries.allocator = p.allocator
		}
		
		header := runtime.__get_map_header_runtime(raw_map, t)
		
		elem_backing := bytes_make(t.value.size, t.value.align, p.allocator) or_return
		defer delete(elem_backing, p.allocator)
		
		map_backing_value := any{raw_data(elem_backing), t.value.id}
		
		pass := 0
		
		map_loop: for p.curr_token.kind != .Close_Brace {
			defer pass += 1
			
			key, _ := parse_object_key(p, p.allocator)
			unmarsal_expect_token(p, .Colon)
			
			
			mem.zero_slice(elem_backing)
			if err := unmarsal_value(p, map_backing_value); err != nil {
				delete(key, p.allocator)
				return err
			}
			
			hash := runtime.Map_Hash {
				hash = runtime.default_hasher_string(&key, 0),
				key_ptr = &key,
			}
			
			key_cstr: cstring
			if reflect.is_cstring(t.key) {
				key_cstr = cstring(raw_data(key))
				hash.key_ptr = &key_cstr
			}
			
			set_ptr := runtime.__dynamic_map_set(header, hash, map_backing_value.data)
			if set_ptr == nil {
				delete(key, p.allocator)
			} 
		
			if p.spec == Specification.JSON5 {
				// Allow trailing commas
				if allow_token(p, .Comma) {
					continue map_loop
				}
			} else {
				// Disallow trailing commas
				if allow_token(p, .Comma) {
					continue map_loop
				} else {
					break map_loop
				}
			}
		}
		
	case reflect.Type_Info_Enumerated_Array:
		index_type := reflect.type_info_base(t.index)
		enum_type := index_type.variant.(reflect.Type_Info_Enum)
	
		enumerated_array_loop: for p.curr_token.kind != .Close_Brace {
			key, _ := parse_object_key(p, p.allocator)
			unmarsal_expect_token(p, .Colon)
			defer delete(key, p.allocator)

			index := -1
			for name, i in enum_type.names {
				if key == name {
					index = int(enum_type.values[i] - t.min_value)
					break
				}
			}
			if index < 0 || index >= t.count {
				return UNSUPPORTED_TYPE
			}
						
			index_ptr := rawptr(uintptr(v.data) + uintptr(index*t.elem_size))
			index_any := any{index_ptr, t.elem.id}
			
			unmarsal_value(p, index_any) or_return
		
			if p.spec == Specification.JSON5 {
				// Allow trailing commas
				if allow_token(p, .Comma) {
					continue enumerated_array_loop
				}
			} else {
				// Disallow trailing commas
				if allow_token(p, .Comma) {
					continue enumerated_array_loop
				} else {
					break enumerated_array_loop
				}
			}
		}

		return nil
	
	case:
		return UNSUPPORTED_TYPE
	}
	
	assert(expect_token(p, .Close_Brace) == nil)
	return
}


@(private)
unmarsal_count_array :: proc(p: ^Parser) -> (length: uintptr) {
	p_backup := p^
	p.allocator = mem.nil_allocator()
	unmarsal_expect_token(p, .Open_Bracket)
	array_length_loop: for p.curr_token.kind != .Close_Bracket {
		_, _ = parse_value(p)
		length += 1

		if allow_token(p, .Comma) {
			continue
		} else {
			break
		}
	}
	p^ = p_backup
	return
}

@(private)
unmarsal_array :: proc(p: ^Parser, v: any) -> (err: Unmarshal_Error) {
	assign_array :: proc(p: ^Parser, base: rawptr, elem: ^reflect.Type_Info, length: uintptr) -> Unmarshal_Error {
		unmarsal_expect_token(p, .Open_Bracket)
		
		for idx: uintptr = 0; p.curr_token.kind != .Close_Bracket; idx += 1 {
			assert(idx < length)
			
			elem_ptr := rawptr(uintptr(base) + idx*uintptr(elem.size))
			elem := any{elem_ptr, elem.id}
			
			unmarsal_value(p, elem) or_return
			
			if allow_token(p, .Comma) {
				continue
			} else {
				break
			}	
		}
		
		unmarsal_expect_token(p, .Close_Bracket)
		
		
		return nil
	}

	UNSUPPORTED_TYPE := Unsupported_Type_Error{v.id, p.curr_token}
	
	ti := reflect.type_info_base(type_info_of(v.id))
	
	length := unmarsal_count_array(p)
	
	#partial switch t in ti.variant {
	case reflect.Type_Info_Slice:	
		raw := (^mem.Raw_Slice)(v.data)
		data := bytes_make(t.elem.size * int(length), t.elem.align, p.allocator) or_return
		raw.data = raw_data(data)
		raw.len = int(length)
			
		return assign_array(p, raw.data, t.elem, length)
		
	case reflect.Type_Info_Dynamic_Array:
		raw := (^mem.Raw_Dynamic_Array)(v.data)
		data := bytes_make(t.elem.size * int(length), t.elem.align, p.allocator) or_return
		raw.data = raw_data(data)
		raw.len = int(length)
		raw.cap = int(length)
		raw.allocator = p.allocator
		
		return assign_array(p, raw.data, t.elem, length)
		
	case reflect.Type_Info_Array:
		// NOTE(bill): Allow lengths which are less than the dst array
		if int(length) > t.count {
			return UNSUPPORTED_TYPE
		}
		
		return assign_array(p, v.data, t.elem, length)
		
	case reflect.Type_Info_Enumerated_Array:
		// NOTE(bill): Allow lengths which are less than the dst array
		if int(length) > t.count {
			return UNSUPPORTED_TYPE
		}
		
		return assign_array(p, v.data, t.elem, length)
	}
		
	return UNSUPPORTED_TYPE
}