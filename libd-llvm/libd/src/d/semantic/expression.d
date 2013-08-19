module d.semantic.expression;

import d.semantic.identifiable;
import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.base;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;

import std.algorithm;
import std.array;
import std.range;

alias BinaryExpression = d.ir.expression.BinaryExpression;
alias UnaryExpression = d.ir.expression.UnaryExpression;
alias CallExpression = d.ir.expression.CallExpression;
alias NewExpression = d.ir.expression.NewExpression;
alias IndexExpression = d.ir.expression.IndexExpression;
alias SliceExpression = d.ir.expression.SliceExpression;
alias AssertExpression = d.ir.expression.AssertExpression;

alias PointerType = d.ir.type.PointerType;
alias SliceType = d.ir.type.SliceType;
alias ArrayType = d.ir.type.ArrayType;
alias FunctionType = d.ir.type.FunctionType;
alias DelegateType = d.ir.type.DelegateType;

final class ExpressionVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(AstExpression e) {
		return this.dispatch(e);
	}
	
	Expression visit(ParenExpression e) {
		return visit(e.expr);
	}
	
	Expression visit(BooleanLiteral e) {
		return e;
	}
	
	Expression visit(IntegerLiteral!true e) {
		return e;
	}
	
	Expression visit(IntegerLiteral!false e) {
		return e;
	}
	
	Expression visit(FloatLiteral e) {
		return e;
	}
	
	Expression visit(CharacterLiteral e) {
		return e;
	}
	
	Expression visit(StringLiteral e) {
		return e;
	}
	
	private Expression getTemporaryLvalue(Expression value) {
		auto pt = QualType(new PointerType(value.type));
		auto ptr = new UnaryExpression(value.location, pt, UnaryOp.AddressOf, value);
		auto s = new SymbolExpression(value.location, new Variable(value.location, pt, "", ptr));
		
		return new UnaryExpression(value.location, value.type, UnaryOp.Dereference, s);
	}
	
	private Expression getTemporaryRvalue(Expression value) {
		return new SymbolExpression(value.location, new Variable(value.location, value.type, "", value));
	}
	
	Expression visit(AstBinaryExpression e) {
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		auto op = e.op;
		
		QualType type;
		final switch(op) with(BinaryOp) {
			case Comma:
				type = rhs.type;
				break;
			
			case Assign :
				type = lhs.type;
				rhs = buildImplicitCast(rhs.location, type, rhs);
				break;
			
			case Add :
			case Sub :
				if(auto pt = cast(PointerType) peelAlias(lhs.type).type) {
					// FIXME: check that rhs is an integer.
					if(op == Sub) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, pt.pointed, lhs, [rhs]);
					return new UnaryExpression(e.location, lhs.type, UnaryOp.AddressOf, i);
				}
				
				goto case;
			
			case Mul :
			case Div :
			case Mod :
			case Pow :
				type = getPromotedType(e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(lhs.location, type, lhs);
				rhs = buildImplicitCast(rhs.location, type, rhs);
				
				break;
			
			case AddAssign :
			case SubAssign :
				if(auto pt = cast(PointerType) peelAlias(lhs.type).type) {
					// FIXME: check that rhs is an integer.
					if(op == SubAssign) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, pt.pointed, lhs, [rhs]);
					auto v = new UnaryExpression(e.location, lhs.type, UnaryOp.AddressOf, i);
					return new BinaryExpression(e.location, lhs.type, Assign, lhs, v);
				}
				
				goto case;
			
			case MulAssign :
			case DivAssign :
			case ModAssign :
			case PowAssign :
				type = lhs.type;
				
				rhs = buildImplicitCast(rhs.location, type, rhs);
				
				break;
			
			case Concat :
			case ConcatAssign :
				assert(0, "Not implemented.");
			
			case LogicalOr :
			case LogicalAnd :
				type = getBuiltin(TypeKind.Bool);
				
				lhs = buildExplicitCast(lhs.location, type, lhs);
				rhs = buildExplicitCast(rhs.location, type, rhs);
				
				break;
			
			case LogicalOrAssign :
			case LogicalAndAssign :
			case BitwiseOr :
			case BitwiseAnd :
			case BitwiseXor :
			case BitwiseOrAssign :
			case BitwiseAndAssign :
			case BitwiseXorAssign :
				assert(0, "Not implemented.");
			
			case Equal :
			case NotEqual :
			case Identical :
			case NotIdentical :
				type = getPromotedType(e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(lhs.location, type, lhs);
				rhs = buildImplicitCast(rhs.location, type, rhs);
				
				type = getBuiltin(TypeKind.Bool);
				
				break;
			
			case In :
			case NotIn :
			case LeftShift :
			case SignedRightShift :
			case UnsignedRightShift :
			case LeftShiftAssign :
			case SignedRightShiftAssign :
			case UnsignedRightShiftAssign :
				assert(0, "Not implemented.");
			
			case Greater :
			case GreaterEqual :
			case Less :
			case LessEqual :
				type = getPromotedType(e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(lhs.location, type, lhs);
				rhs = buildImplicitCast(rhs.location, type, rhs);
				
				type = getBuiltin(TypeKind.Bool);
				
				break;
			
			case LessGreater :
			case LessEqualGreater :
			case UnorderedLess :
			case UnorderedLessEqual :
			case UnorderedGreater :
			case UnorderedGreaterEqual :
			case Unordered :
			case UnorderedEqual :
				assert(0, "Not implemented.");
		}
		
		return new BinaryExpression(e.location, type, op, lhs, rhs);
	}
	
	private Expression handleAddressOf(Expression expr) {
		// For fucked up reasons, &funcname is a special case.
		if(auto se = cast(SymbolExpression) expr) {
			if(cast(Function) se.symbol) {
				return expr;
			}
		} else if(auto pe = cast(PolysemousExpression) expr) {
			pe.expressions = pe.expressions.map!(e => handleAddressOf(e)).array();
			return pe;
		}
		
		return new UnaryExpression(expr.location, QualType(new PointerType(expr.type)), UnaryOp.AddressOf, expr);
	}
	
	Expression visit(AstUnaryExpression e) {
		auto expr = visit(e.expr);
		auto op = e.op;
		
		QualType type;
		final switch(op) with(UnaryOp) {
			case AddressOf :
				return handleAddressOf(expr);
				// It could have been so simple :(
				/+
				type = QualType(new PointerType(expr.type));
				break;
				+/
			
			case Dereference :
				if(auto pt = cast(PointerType) peelAlias(expr.type).type) {
					type = pt.pointed;
					break;
				}
				
				return pass.raiseCondition!Expression(e.location, "Only pointers can be dereferenced, not " ~ expr.type.toString());
			
			case PreInc :
			case PreDec :
			case PostInc :
			case PostDec :
				if(auto pt = cast(PointerType) peelAlias(expr.type).type) {
					expr = getTemporaryLvalue(expr);
					
					Expression n = new IntegerLiteral!true(e.location, (op == PreInc || op == PostInc)? 1 : -1, TypeKind.Ulong);
					auto i = new IndexExpression(e.location, pt.pointed, expr, [n]);
					auto v = new UnaryExpression(e.location, expr.type, AddressOf, i);
					auto r = new BinaryExpression(e.location, expr.type, BinaryOp.Assign, expr, v);
					
					if(op == PreInc || op == PreDec) {
						return r;
					}
					
					auto l = getTemporaryRvalue(expr);
					r = new BinaryExpression(e.location, expr.type, BinaryOp.Comma, l, r);
					return new BinaryExpression(e.location, expr.type, BinaryOp.Comma, r, l);
				}
				
				type = expr.type;
				break;
			
			case Plus :
			case Minus :
				// FIXME: check that type is integer.
				type = expr.type;
				break;
			
			case Not :
				type = getBuiltin(TypeKind.Bool);
				expr = buildExplicitCast(expr.location, type, expr);
				break;
			
			case Complement :
				assert(0, "Not implemented.");
		}
		
		return new UnaryExpression(e.location, type, op, expr);
	}
	
	Expression visit(AstCastExpression e) {
		auto to = pass.visit(e.type);
		return buildExplicitCast(e.location, to, visit(e.expr));
	}
	
	private auto buildArgument(Expression arg, ParamType pt) {
		if(pt.isRef && !canConvert(arg.type.qualifier, pt.qualifier)) {
			return pass.raiseCondition!Expression(arg.location, "Can't pass argument by ref.");
		}
		
		arg = pass.buildImplicitCast(arg.location, QualType(pt.type, pt.qualifier), arg);
		
		// test if we can pass by ref.
		if(pt.isRef && !arg.isLvalue) {
			return pass.raiseCondition!Expression(arg.location, "Argument isn't a lvalue.");
		}
		
		return arg;
	}
	
	enum MatchLevel {
		Not,
		TypeConvert,
		QualifierConvert,
		Exact,
	}
	
	// TODO: deduplicate.
	private auto matchArgument(Expression arg, ParamType param) {
		if(param.isRef && !canConvert(arg.type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}
		
		auto flavor = pass.implicitCastFrom(arg.type, QualType(param.type, param.qualifier));
		
		// test if we can pass by ref.
		if(param.isRef && !(flavor >= CastKind.Bit && arg.isLvalue)) {
			return MatchLevel.Not;
		}
		
		return matchLevel(flavor);
	}
	
	// TODO: deduplicate.
	private auto matchArgument(ParamType type, ParamType param) {
		if(param.isRef && !canConvert(type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}
		
		auto flavor = pass.implicitCastFrom(QualType(type.type, type.qualifier), QualType(param.type, param.qualifier));
		
		// test if we can pass by ref.
		if(param.isRef && !(flavor >= CastKind.Bit && type.isRef)) {
			return MatchLevel.Not;
		}
		
		return matchLevel(flavor);
	}
	
	private auto matchLevel(CastKind flavor) {
		final switch(flavor) with(CastKind) {
			case Invalid :
				return MatchLevel.Not;
			
			case IntegralToBool :
			case Trunc :
			case Pad :
			case Bit :
				return MatchLevel.TypeConvert;
			
			case Qual :
				return MatchLevel.QualifierConvert;
			
			case Exact :
				return MatchLevel.Exact;
		}
	}
	
	Expression visit(AstCallExpression c) {
		auto callee = visit(c.callee);
		auto args = c.arguments.map!(a => visit(a)).array();
		
		if(auto asPolysemous = cast(PolysemousExpression) callee) {
			auto candidates = asPolysemous.expressions.filter!((e) {
				if(auto asFunType = cast(FunctionType) peelAlias(e.type).type) {
					if(asFunType.isVariadic) {
						return args.length >= asFunType.paramTypes.length;
					} else {
						return args.length == asFunType.paramTypes.length;
					}
				}
				
				assert(0, "type is not a function type");
			});
			
			auto level = MatchLevel.Not;
			Expression match;
			CandidateLoop: foreach(candidate; candidates) {
				auto type = cast(FunctionType) peelAlias(candidate.type).type;
				assert(type, "We should have filtered function at this point.");
				
				auto candidateLevel = MatchLevel.Exact;
				foreach(arg, param; lockstep(args, type.paramTypes)) {
					auto argLevel = matchArgument(arg, param);
					
					// If we don't match high enough.
					if(argLevel < level) {
						continue CandidateLoop;
					}
					
					final switch(argLevel) with(MatchLevel) {
						case Not :
							// This function don't match, go to next one.
							continue CandidateLoop;
						
						case TypeConvert :
						case QualifierConvert :
							candidateLevel = min(candidateLevel, argLevel);
							continue;
						
						case Exact :
							// Go to next argument
							continue;
					}
				}
				
				if(candidateLevel > level) {
					level = candidateLevel;
					match = candidate;
				} else if(candidateLevel == level) {
					// Check for specialisation.
					auto matchType = cast(FunctionType) peelAlias(match.type).type;
					assert(matchType, "We should have filtered function at this point.");
					
					bool candidateFail;
					bool matchFail;
					foreach(param, matchParam; lockstep(type.paramTypes, matchType.paramTypes)) {
						if(matchArgument(param, matchParam) == MatchLevel.Not) {
							candidateFail = true;
						}
						
						if(matchArgument(matchParam, param) == MatchLevel.Not) {
							matchFail = true;
						}
					}
					
					if(matchFail == candidateFail) {
						return pass.raiseCondition!Expression(c.location, "ambigusous function call.");
					}
					
					if(matchFail) {
						match = candidate;
					}
				}
			}
			
			if(!match) {
				return pass.raiseCondition!Expression(c.location, "No candidate for function call.");
			}
			
			callee = match;
		}
		
		auto type = peelAlias(callee.type).type;
		ParamType[] paramTypes;
		ParamType returnType;
		if(auto f = cast(FunctionType) type) {
			paramTypes = f.paramTypes;
			returnType = f.returnType;
		} else if(auto d = cast(DelegateType) type) {
			paramTypes = d.paramTypes;
			returnType = d.returnType;
		} else {
			return pass.raiseCondition!Expression(c.location, "You must call function or delegates, not " ~ callee.type.toString());
		}
		
		assert(args.length >= paramTypes.length);
		
		foreach(ref arg, pt; lockstep(args, paramTypes)) {
			arg = buildArgument(arg, pt);
		}
		
		return new CallExpression(c.location, QualType(returnType.type, returnType.qualifier), callee, args);
	}
	
	/+
	Expression visit(FieldExpression e) {
		e.expression = visit(e.expression);
		
		auto f = e.field;
		scheduler.require(f, Step.Signed);
		
		e.type = e.field.type;
		return e;
	}
	
	// TODO: handle overload sets.
	Expression visit(DelegateExpression e) {
		e.funptr = visit(e.funptr);
		
		if(auto funType = cast(FunctionType) e.funptr.type) {
			if(typeid(funType) !is typeid(FunctionType)) {
				return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
			}
			
			if(funType.isVariadic || funType.parameters.length > 0) {
				auto contextParam = funType.parameters[0];
				
				e.context = buildArgument(e.context, contextParam);
				e.type = new DelegateType(funType.linkage, funType.returnType, contextParam, funType.parameters[1 .. $], funType.isVariadic);
				
				return e;
			}
		}
		
		return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
	}
	
	Expression visit(MethodExpression e) {
		auto m = e.method;
		scheduler.require(e.method, Step.Signed);
		
		if(auto dgType = cast(DelegateType) m.type) {
			e.expression = buildArgument(e.expression, dgType.context);
			e.type = dgType;
			
			return e;
		}
		
		return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
	}
	+/
	Expression visit(AstNewExpression e) {
		assert(e.arguments.length == 0, "constructor not supported");
		
		return new NewExpression(e.location, pass.visit(e.type), []);
	}
	
	Expression visit(ThisExpression e) {
		e.type = QualType(thisType.type, thisType.qualifier);
		
		return e;
	}
	
	Expression visit(AstIndexExpression e) {
		auto indexed = visit(e.indexed);
		
		auto qt = peelAlias(indexed.type);
		auto type = qt.type;
		if(auto asSlice = cast(SliceType) type) {
			qt = asSlice.sliced;
		} else if(auto asPointer = cast(PointerType) type) {
			qt = asPointer.pointed;
		} else if(auto asArray = cast(ArrayType) type) {
			qt = asArray.elementType;
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't index " ~ indexed.type.toString());
		}
		
		auto arguments = e.arguments.map!(e => visit(e)).array();
		
		return new IndexExpression(e.location, qt, indexed, arguments);
	}
	
	Expression visit(AstSliceExpression e) {
		// TODO: check if it is valid.
		auto sliced = visit(e.sliced);
		
		auto qt = peelAlias(sliced.type);
		auto type = qt.type;
		if(auto asSlice = cast(SliceType) type) {
			qt.type = asSlice.sliced.type;
		} else if(auto asPointer = cast(PointerType) type) {
			qt.type = asPointer.pointed.type;
		} else if(auto asArray = cast(ArrayType) type) {
			qt.type = asArray.elementType.type;
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't slice " ~ sliced.type.toString());
		}
		
		auto first = e.first.map!(e => visit(e)).array();
		auto second = e.second.map!(e => visit(e)).array();
		
		return new SliceExpression(e.location, QualType(new SliceType(qt)), sliced, first, second);
	}
	
	Expression visit(AstAssertExpression e) {
		auto c = visit(e.condition);
		c = buildExplicitCast(c.location, getBuiltin(TypeKind.Bool), c);
		
		Expression msg;
		if(e.message) {
			msg = visit(e.message);
			
			// TODO: ensure that msg is a string.
		}
		
		return new AssertExpression(e.location, getBuiltin(TypeKind.Void), c, msg);
	}
	
	Expression visit(IdentifierExpression e) {
		return pass.visit(e.identifier).apply!((identified) {
			static if(is(typeof(identified) : Expression)) {
				return identified;
			} else {
				return pass.raiseCondition!Expression(e.location, e.identifier.name ~ " isn't an expression.");
			}
		})();
	}
}

