using CSV
using XLSX
using DataFrames
using ProgressMeter

# 当前目录
parent_path = replace(@__DIR__, "\\"=>"/")

include("$parent_path/main_dis_sheet.jl")
include("$parent_path/drg_dict.jl")
include("$parent_path/adrg_dis_list.jl")
include("$parent_path/all_surgery.jl")
include("$parent_path/CCMCC.jl")
include("$parent_path/exclusive_sheet.jl")

# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\main_dis_sheet.jl")
# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\drg_dict.jl")
# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\adrg_dis_list.jl")
# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\all_surgery.jl")
# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\CCMCC.jl")
# include("D:\\MyProgram\\DRG_GROUPER\\julia_drg\\exclusive_sheet.jl")


# 判断属于哪个ADRG
function which_adrg(record::drg_case)
	result_MDC = "KBBZ"
	result_ADRG = "KBBZ"

	# 这里设置遍历从MDCA => MDCP => MDCY => MDCZ的优先考虑
	for mdc in ["MDCA", "MDCP", "MDCY", "MDCZ", "MDCB", "MDCC", "MDCD", "MDCE", "MDCF", "MDCG", "MDCH", "MDCI",
			    "MDCJ", "MDCK", "MDCL", "MDCM", "MDCN", "MDCO", "MDCQ", "MDCR", "MDCS", "MDCT", "MDCU", "MDCV",
			    "MDCW", "MDCX"]

		# 先期分组MDCA
		if mdc == "MDCA"
			result_ADRG = is_MDCA(record)
			if result_ADRG != "KBBZ"
				result_MDC = "MDCA"

				return (result_ADRG, result_MDC)
			end

		# 高优先级MDCP
		elseif mdc == "MDCP"
			verb = Symbol(mdc * "_main_dis_list")
			result_MDC = is_age_mdc(record, eval(verb), mdc)
			if result_MDC != "KBBZ"
				for adrg in mdc_map_adrg[mdc]
					result_ADRG = process_adrg(record, adrg)
					if result_ADRG != "KBBZ"
						result_MDC == mdc
						return (result_ADRG, result_MDC)
					end
				end
			end


		# 高优先级MDCZ
		elseif mdc == "MDCZ"
			result_MDC = is_MDCZ(record)
			if result_MDC != "KBBZ"
				for adrg in mdc_map_adrg[mdc]
					result_ADRG = process_adrg(record, adrg)
					if result_ADRG != "KBBZ"
						result_ADRG == mdc
						return (result_ADRG, result_MDC)
					end
				end
			end


		# 需要判断性别的MDC
		elseif (mdc == "MDCM") || (mdc == "MDCN")
			verb = Symbol(mdc * "_main_dis_list")
			# 如果能进入MDC
			result_MDC = is_sex_mdc(record, eval(verb), mdc)
			if result_MDC != "KBBZ"
				for adrg in mdc_map_adrg[mdc]
					result_ADRG = process_adrg(record, adrg)
					if result_ADRG != "KBBZ"
						result_MDC == mdc
						return (result_ADRG, result_MDC)
					end
				end
			end

		# 其他正常凭借主诊断进入的MDC(MDCY也在此)
		else
			verb = Symbol(mdc * "_main_dis_list")
			# 如果能进入MDC
			result_MDC = is_common_mdc(record, eval(verb), mdc)
			if result_MDC != "KBBZ"
				for adrg in mdc_map_adrg[mdc]
					result_ADRG = process_adrg(record, adrg)
					if result_ADRG != "KBBZ"
						result_MDC == mdc
						return (result_ADRG, result_MDC)
					end
				end
			end
		end
	
	end
	# 全部都没有
	return (result_ADRG, result_MDC)

end

# 判断是否为QY
function is_qy(record::drg_case, adrg_pred::AbstractString, mdc_pred::AbstractString)
	# 判断是否为
	if (mdc_pred != "KBBZ")
		if (adrg_pred != "KBBZ")
			# 判断ADRG的类型
			adrg_pred_type = adrg_type_dict[adrg_pred][1]

			# 这几个ADRG属于包含全部手术都可以的, 不会出现QY
			if adrg_pred in ["YC1","SB1","XJ1","TB1"]
				return (adrg_pred, mdc_pred)
			end

			# 如果无手术(由于手术病例的主手术必填, 无主手术的病例自然不会是手术病例, 也不会是QY)
			if no_surgery(record)
				return (adrg_pred, mdc_pred)
			end
			
			# 判断是否无其他手术
			cross = no_other_surgery(record) ? [record.main_dis] : [record.other_opt..., record.main_opt]
			if (adrg_pred_type == "内科") && (length(intersect(cross, all_surgery_list)) > 0)
				adrg_pred = mdc_pred[end] * "QY"
			end

		end
	end

	return (adrg_pred, mdc_pred)
end


# 判断是否严重或一般并发症(需要先排除QY与KBBZ)
function which_ccmcc(record::drg_case, adrg_pred::String, mdc_pred::String)
	res_lab = ""  # 最后的并发症类型
	complication_list = Union{String, Nothing}[]
	exclude_pos = ""
	complication = ""

	# 如果该ADRG没有进行并发症细分, 则并发症类型为9
	if adrg_type_dict[adrg_pred][2] == "未细分"
		res_lab = "9"
		return res_lab
	end

	# 如果无其他诊断, 则该病例没有不伴并发症
	if no_other_diagnosis(record)
		res_lab = "5"
		return res_lab
	end

	# 有其他诊断的情况下, 逐一检查是否为CC或MCC, 是否被排除
	for d in record.other_dis
		exclude_pos, complication = get(cc_mcc_dict, d, (nothing, nothing))
		# 有并发症严重或一般
		if (complication !== nothing) || (exclude_pos == "无")
			# 是否被排除
			is_exclude = get(exclusive_dict, record.main_dis, nothing)
			if is_exclude !== nothing
				push!(complication_list, complication)
			else
				push!(complication, nothing)
			end
		else
			push!(complication_list, nothing)
		end
	end

	complication_list = filter(x -> x !== nothing, complication_list)


	# 一合并三没有一, 三合并五没有五
	if adrg_type_dict[adrg_pred][2] == "1合并3"
		if length(complication_list) == 0
			res_lab = "5"
		else
			res_lab = "3"
		end

	elseif adrg_type_dict[adrg_pred][2] == "3合并5"
		if "MCC" in complication_list
			res_lab = "1"
		else
			res_lab = "5"
		end

	# 无合并1,3,5的情况
	else
		if length(complication_list) == 0
			res_lab = "5"
		elseif "MCC" in complication_list
			res_lab = "1"
		else
			res_lab = "3"
		end
	end

	return res_lab

end


# 联合上述两个函数, 判断进入那个DRG
function which_drg(record::drg_case)
	adrg, mdc = which_adrg(record)
	adrg, mdc = is_qy(record, adrg, mdc)
	if (adrg != "KBBZ") && (adrg[2:3] != "QY")
		complication_lab = which_ccmcc(record, adrg, mdc)
		return adrg * complication_lab
	else
		return adrg
	end
end


# 转换诊断编码为大写
function translate_code(code::Union{AbstractString, Missing})
	if ismissing(code)
		return code
	else
		return reduce((x,y) -> string(x, y), [i != 'x' ? uppercase(i) : i for i in code])
	end
end

# 读取表格数据文件excel
function read_excel(file_path::String)
	df = DataFrame(XLSX.readtable(file_path, "Sheet1")...)
	return df
end

# 读取表格数据文件CSV
function read_csv(file_path::String)
	df = DataFrame(CSV.File(file_path))
	return df
end

# 读取表格数据并给每一个病例进行分组
function batch_group(df::DataFrame)
	drg_code_list = []
	@showprogress 1 "Computing..." for row in 1:size(df)[1]
		# 将其他诊断手术合并为一个向量
		dis_columns = ["其他诊断"*string(i) for i in 1:15] |> arr -> map(x -> Symbol(x), arr)
		opt_columns = ["其他手术编码"*string(i) for i in 1:10] |> arr -> map(x -> Symbol(x), arr)
		other_dis_list = [translate_code(df[!,i][row]) for i in dis_columns] |> arr -> String[filter(x -> !ismissing(x), arr)...]
		other_opt_list = [translate_code(df[!,i][row]) for i in dis_columns] |> arr -> String[filter(x -> !ismissing(x), arr)...]
		
		# 结构化单个病例
		single_case = drg_case(
			df[!,:结算流水号][row],
			"B30.301+H13.1*",
			ismissing(df[!,:主手术编码][row]) ? "" : df[!,:主手术编码][row],
			other_dis_list,
			other_opt_list,
			df[!,:性别][row],
			df[!,:年龄][row],
			0
		)

		# 判断进入那个DRG组
		drg_code = which_drg(single_case)
		push!(drg_code_list, drg_code)
	end
	
	return drg_code_list
end



# 测试=====================================================================
# case1 = drg_case(
# 	"450100G0000013711024",
# 	"C45.100",
# 	"39.6500",
# 	["A01.000x009", "A08.400x003", "A20.802"],
# 	["79.6201", "38.8700x008"],
# 	1,
# 	0.03,
# 	2879
# )

# case2 = drg_case(
# 	"450100G0000013712186",
# 	"C53.800",
# 	"04.3x01",
# 	["E16.800x901","N70.101","N72.x00x003","N73.602","N83.201"],
# 	["54.5100x009","71.5x00x004","54.4x00x007",],
# 	0,
# 	57,
# 	28790
# )

println("读取数据===================================================")
data = read_excel("D:\\MyProgram\\DRG_GROUPER\\测试数据.xlsx")


println("开始批量分组================================================")

data.测算分组编码 = batch_group(data)

CSV.write("D:\\MyProgram\\DRG_GROUPER\\分组结果.CSV", data)


# res1 = which_drg(case1)
# res2 = which_drg(case2)
# println(res1)
# println(res2)








