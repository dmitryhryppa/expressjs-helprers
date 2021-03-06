package express;

import haxe.ds.StringMap;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.PositionTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;

using haxe.macro.ExprTools;
using haxe.macro.MacroStringTools;
using haxe.macro.TypeTools;

final class RouterBuilder {
	public static function build():Array<Field> {
		final pos:Position = Context.currentPos();
		final fields:Array<Field> = Context.getBuildFields();
		final ct:ClassType = Context.getLocalClass().get();

		fields.push({
			name: "__router",
			access: [APublic, AFinal],
			kind: FVar(macro:Dynamic, macro {js.npm.express.Express.router();}),
			meta: [{name: ":keep", pos: pos}, {name: ":noCompletion", pos: pos}],
			pos: pos
		});

		final routeFuncs:Array<{name:String, method:String, path:String}> = [];

		for (field in fields) {
			switch field.kind {
				case FFun(f):
					if (field.meta != null) {
						for (meta in field.meta) {
							if (meta.params.length > 0) {
								if (meta.name == Get || meta.name == Post || meta.name == Put || meta.name == Delete) {
									final pack:Array<String> = ["js", "npm", "express"];
									final prevArgs:Array<FunctionArg> = f.args;

									f.args = [];
									f.args.push({
										name: "req",
										type: TPath({pack: pack, name: "EReq"})
									});

									f.args.push({
										name: "res",
										type: TPath({pack: pack, name: "EResp"})
									});

									switch meta.params[0].expr {
										case EConst(CString(s)):
											routeFuncs.push({
												name: field.name,
												method: meta.name,
												path: s
											});
										case _:
									}

									if (prevArgs.length > 0) {
										function buildVar(arg:FunctionArg):Var {
											final stdMethod:Null<String> = switch (arg.type) {
												case TPath(p):
													switch (p.name) {
														case "String": "string";
														case "Float": "parseFloat";
														case "Int": "parseInt";
														case _: null;
													}
												case _: null;
											};

											inline function e(expr:ExprDef):Expr
												return {expr: expr, pos: pos};

											final queryExprField:Expr = ["req", meta.name == Get ? "query" : "body", arg.name].toFieldExpr(pos);
											return switch stdMethod {
												case null: {
														name: arg.name,
														type: arg.type,
														expr: queryExprField,
														isFinal: true
													}
												case "string": {
														name: arg.name,
														type: TPath({pack: [], name: "Null", params: [TPType(arg.type)]}),
														expr: {
															expr: ETernary(e(EBinop(OpEq, queryExprField, macro null)), macro null,
																e(ECall(["Std", stdMethod].toFieldExpr(), [queryExprField]))),
															pos: pos
														},
														isFinal: true
													}
												case _: {
														name: arg.name,
														type: TPath({pack: [], name: "Null", params: [TPType(arg.type)]}),
														expr: {
															expr: ECall(["Std", stdMethod].toFieldExpr(), [queryExprField]),
															pos: pos
														},
														isFinal: true
													}
											}
										};

										final varsExpr:Expr = {
											expr: EVars([
												for (arg in prevArgs)
													buildVar(arg)
											]),
											pos: pos
										};

										final badRequestExpr:Expr = e(ECall(["res", "send"].toFieldExpr(),
											[e(EConst(CInt("400")), pos), e(EConst(CString("Bad request.")), pos)]), pos);

										function buildCheckExpressions():Expr {
											var prevExpr:Null<Expr> = null;
											for (arg in prevArgs) {
												final queryExprField:Expr = ["req", meta.name == Get ? "query" : "body", arg.name].toFieldExpr(pos);
												final currentExpr:Expr = {
													expr: EBinop(OpEq, queryExprField, {
														expr: EConst(CIdent("null")),
														pos: pos
													}),
													pos: pos
												};
												if (prevExpr == null) {
													prevExpr = currentExpr;
												} else {
													prevExpr = {
														expr: EBinop(OpBoolAnd, prevExpr, currentExpr),
														pos: pos
													};
												}
											}

											return prevExpr;
										}

										f.expr = {
											expr: EIf(buildCheckExpressions(), badRequestExpr, macro @:mergeBlock {
												${varsExpr};
												${f.expr};
											}),
											pos: pos
										};
									}
								}
							}
						}
					}
				case FVar(t, e):
				case FProp(get, set, t, e):
			}
		}

		var contructor:Null<Function> = null;
		for (field in fields) {
			switch field.kind {
				case FFun(f):
					if (field.name == "new") {
						contructor = f;
					};
				default:
			};
		}

		if (contructor == null) {
			contructor = {
				args: [],
				expr: {
					expr: EBlock([]),
					pos: pos
				},
				params: [],
				ret: null
			};
			fields.push({
				name: "new",
				access: [APublic],
				pos: pos,
				kind: FFun(contructor)
			});
		}

		final constrExpr = contructor.expr;
		final varsExpr:Expr = {
			expr: EBlock([
				for (route in routeFuncs)
					{
						expr: ECall({
							expr: EField({
								expr: EConst(CIdent("__router")),
								pos: pos
							}, StringTools.replace(route.method, ":", "")),
							pos: pos
						}, [
							{expr: EConst(CString(route.path)), pos: pos},
							{
								expr: EField({
									expr: EConst(CIdent("this")),
									pos: pos
								}, route.name),
								pos: pos
							}
						]),
						pos: pos
					}
			]),
			pos: pos
		};
		contructor.expr = macro @:mergeBlock {
			${contructor.expr};
			$varsExpr;
		};

		return fields;
	}

	private static inline function e(exprDef:ExprDef, pos:Position):Expr {
		return {
			expr: exprDef,
			pos: pos
		};
	}
}

private enum abstract MetaName(String) from String to String {
	var Get = ":get";
	var Post = ":post";
	var Put = ":put";
	var Delete = ":delete";
}
