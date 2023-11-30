
# 病例的结构体
struct drg_case
	id::String                                             # 病例ID
	main_dis::String                                       # 主诊断编码(必填)
	main_opt::Union{String,Nothing}                        # 主手术编码(手术或操作病例则必填)
	other_dis::Vector{Union{String,Nothing}}       		   # 其他诊断编码(向量)
	other_opt::Vector{Union{String,Nothing}}       		   # 其他手术编码(向量)
	sex::Int                        					   # 性别(男 => 1, 女 => 0)
	age::Float64                    					   # 年龄(小于1岁, 为小数, 否则为整数)
	weight::Int                     					   # 体重(克g)
end

# ADRG结构体
# struct adrg
# 	name::String
# 	main_dis_sheet::Vector{String}
# 	main_opt_sheet::Vector{String}
# 	dis_sheet::Vector{String}
# 	opt_sheet::Vector{String}
# 	other_opt_sheet1::Vector{String}
# 	other_opt_sheet2::Vector{String}
# 	other_opt_sheet3::Vector{String}
# 	other_opt_sheet4::Vector{String}
# end


# 病例检查===========================================================================================
# 检查该病例是否有主手术
function no_surgery(record::drg_case)
	return (record.main_opt == "") || (record.main_opt === nothing)
end

# 检查是否无其他手术
function no_other_surgery(record::drg_case)
	fil_empty = filter(x -> (x != "") || (x !== nothing), record.other_opt)
	return (length(record.other_opt) == 0) || (length(fil_empty) == 0)
end

# 检查是否无其他诊断
function no_other_diagnosis(record::drg_case)
	fil_empty = filter(x -> (x != "") || (x !== nothing), record.other_dis)
	return (length(record.other_dis) == 0) || (length(fil_empty) == 0)
end


# MDC=============================================================================================
# 先期分组
function is_MDCA(record::drg_case)
	# 如果一个病例没有手术，则不需要判断了
	if no_surgery(record)
		return "KBBZ"
	end

	pred = "KBBZ"
	adrg_list = ["AA1","AB1","AC1","AD1","AE1","AF1","AG1","AG2","AH1"]
	for adrg in adrg_list
		pred = process_adrg(record, adrg)
		if pred != "KBBZ"
			break
		end
	end
	return pred
end

# 多发创伤先期分组
function is_MDCZ(record::drg_case)
	# 判断是否无其他诊断
	total_dis = no_other_diagnosis(record) ? [record.main_dis] : Set([record.other_dis..., record.main_dis])
	pred = []
	# 逐一核查所有诊断是否在不同的部位
	for fragment in ["head_dis", "chest_dis", "belly_dis", "urinary_dis", "reproductive_dis", "torso_spine_dis", "upper_limb_dis", "lower_limb_dis", "bon_dis"]
		temp = intersect(total_dis, MDCZ_main_dis_list[fragment])
		if length(temp) > 0
			if length(pred) == 0
				pred = temp
			else
				pred = [pred..., temp...]
			end
		end
	end
	
	# 如果有两个或两个以上部位的诊断
	if length(pred) > 0
		return "MDCZ"
	else
		return "KBBZ"
	end

end

# 进入MDC判断====================================================================================
# 根据主诊断判断的MDC
function is_common_mdc(record::drg_case, MDC_dis::Vector{String}, MDC_name::String)
	if record.main_dis in MDC_dis
		return MDC_name
	else
		return "KBBZ"
	end
end

# 需要判断主诊断与性别的MDC(MDCM, MDCN)
function is_sex_mdc(record::drg_case, MDC_dis::Vector{String}, MDC_name::String)
	if (MDC_name == "MDCM") (record.sex == 1) && (record.main_dis in MDC_dis)
		return MDC_name
	elseif (MDC_name == "MDCN") (record.sex == 0) && (record.main_dis in MDC_dis)
		return MDC_name
	else
		return "KBBZ"
	end
end

# 需要判断主诊断与年龄的MDC(MDCP)
function is_age_mdc(record::drg_case, MDC_dis::Vector{String}, MDC_name::String)
	if (record.age <= 1/12) && record.main_dis in MDC_dis
		return MDC_name
	else
		return "KBBZ"
	end
end


# 进入ADRG判断=======================================================================================
# 只通过主手术入组的外科ADRG✔
function is_common_surgery_adrg(record::drg_case, ADRG_opt::Vector{String}, ADRG_name::String)
	# 如果一个病例没有手术，则不需要判断了
	if no_surgery(record)
		return "KBBZ"
	end

	if record.main_opt in ADRG_opt
		return ADRG_name
	else
		return "KBBZ"
	end

	return "KBBZ"
end

# 只通过主诊断入组的内科ADRG✔
function is_common_internal_adrg(record::drg_case, ADRG_dis::Vector{String}, ADRG_name::String)
	if record.main_dis in ADRG_dis
		return ADRG_name
	end

	return "KBBZ"
end

# 特殊入组的ADRG => 主诊断 + 主手术✔
function is_both_mdis_and_mopt_adrg(record::drg_case, ADRG_dis::Vector{String}, ADRG_opt::Vector{String}, ADRG_name::String)
	# 如果一个病例没有手术，则不需要判断了
	if no_surgery(record)
		return "KBBZ"
	end

	if (record.main_dis in ADRG_dis) && (record.main_opt in ADRG_opt)
		return ADRG_name
	end

	return "KBBZ"
end

# 特殊入组的ADRG => 主诊断 + 手术(主手术或其他手术)✔
function is_both_mdis_and_opt_adrg(record::drg_case, ADRG_dis::Vector{String}, ADRG_opt1::Vector{String}, ADRG_opt2::Vector{String}, ADRG_name::String)
	# 如果一个病例没有手术，则不需要判断了
	if no_surgery(record)
		return "KBBZ"
	end

	# 先判断病例有没有其他手术
	all_opt_list = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if (record.main_dis) && (length(intersect(all_opt_list, ADRG_opt1)) > 0) && (length(intersect(all_opt_list, ADRG_opt2)) > 0)
		return ADRG_name
	end

	return "KBBZ"
end

# 特殊入组的ADRG => 同时满足两个手术
function is_both_opt_adrg(record::drg_case, ADRG_opt1::Vector{String}, ADRG_opt2::Vector{String}, ADRG_name::String)
	# 由于需要同时满足两个手术, 当病例没有其他手术时, 不可能满足入组条件, 无需判断
	if no_other_surgery(record)
		return "KBBZ"
	end

	all_opt_list = [record.other_opt..., record.main_opt]
	if (length(intersect(all_opt_list, ADRG_opt1)) > 0) && (length(intersect(all_opt_list, ADRG_opt2)) > 0)
		return ADRG_name
	end
	
	return "KBBZ"
end

# 特殊入组的ADRG => 满足主诊断或其他诊断(用于处理PS1、PS2、PS3、PS4)
function is_dis_adrg(record::drg_case, ADRG_dis::Vector{String}, ADRG_name::String)
	# 判断是否无其他诊断
	all_dis_list = no_other_diagnosis(record) ? [record.main_dis] : [record.other_dis..., record.main_dis]
	if length(intersect(all_dis_list, ADRG_dis)) > 0
		if (ADRG_name == "PS1") && (record.weight < 1500)
			return "PS1"
		elseif (ADRG_name == "PS2") && (record.weight >= 1500) && (record.weight < 1999)
			return "PS2"
		elseif (ADRG_name == "PS3") && (record.weight >= 1999) && (record.weight < 2499)
			return "PS3"
		else
			return "PS4"
		end
	end

	return "KBBZ"
end

# 特殊入组的ADRG => 主诊断+手术表1+手术表2，或主诊断+手术表1+手术表3+手术表4
function is_mdis_and_multi_surgery_adrg_one(record::drg_case, ADRG_dis::Vector{String}, ADRG_opt1::Vector{String}, ADRG_opt2::Vector{String}, ADRG_opt3::Vector{String}, ADRG_opt4::Vector{String}, ADRG_name::String)
	# 判断是否无其他手术
	total_opt = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if (record.main_dis in ADRG_dis) && (length(intersect(total_opt, ADRG_opt1)) > 0) && (length(intersect(total_opt, ADRG_opt2)) > 0)
		return ADRG_name
	end

	if (record.main_dis in ADRG_dis) && (length(intersect(total_opt, ADRG_opt1)) > 0) && (length(intersect(total_opt, ADRG_opt3)) > 0) && (length(intersect(total_opt, ADRG_opt4)) > 0)
		return ADRG_name
	end

	return "KBBZ"

end

# 特殊入组的ADRG => 主诊断+手术表1，或主诊断+手术表2+手术表3
function is_mdis_and_multi_surgery_adrg_two(record::drg_case, ADRG_dis::Vector{String}, ADRG_opt1::Vector{String}, ADRG_opt2::Vector{String}, ADRG_opt3::Vector{String}, ADRG_name::String)
	# 判断是否无其他手术
	total_opt = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if (record.main_dis in ADRG_dis) && (length(intersect(total_opt, ADRG_opt1)) > 0)
		return ADRG_name
	end

	if (record.main_dis in ADRG_dis) && (length(intersect(total_opt, ADRG_opt2)) > 0) && (length(intersect(total_opt, ADRG_opt3)) > 0)
		return ADRG_name
	end

	return "KBBZ"

end

# 特殊入组的ADRG包含全部手术
function is_all_surgery(record::drg_case, ADRG_opt::Vector{String}, ADRG_name::String)
	# 判断是否无其他手术
	total_opt = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if length(intersect(total_opt, ADRG_opt)) > 0
		return ADRG_name
	end

	return "KBBZ"
end

# 特殊入组的ADRG => 无手术
function is_without_surgery(record::drg_case, ADRG_opt::Vector{String}, ADRG_name::String)
	# 当病例没有填报任何手术时,符合入组条件
	if no_surgery(record)
		return ADRG_name
	end

	# 判断是否无其他手术
	total_opt = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if length(intersect(total_opt, ADRG_opt)) == 0
		return ADRG_name
	end

	return "KBBZ"
end

# 特殊入组的ADRG包含除WB1以外的手术
function is_no_WB1_surgery(record::drg_case, ADRG_opt::Vector{String}, ADRG_name::String)
	# 没有主手术时, 则不需要判断了
	if no_surgery(record)
		return "KBBZ"
	end

	# 判断是否无其他手术
	total_opt = no_other_surgery(record) ? [record.main_opt] : [record.other_opt..., record.main_opt]
	if length(intersect(total_opt, ADRG_opt)) == 0
		return ADRG_name
	end

	return "KBBZ"
end


# 处理入组=================================================================================
function process_adrg(record::drg_case, ADRG_name::String)
	# 普通ADRG租入, 只用主手术入组
	if adrg_func_dict[ADRG_name] == is_common_surgery_adrg
		verb = Symbol(ADRG_name * "_opt")
		return is_common_surgery_adrg(record, eval(verb), ADRG_name)

	# 普通ADRG入组, 只用主诊断入组
	elseif adrg_func_dict[ADRG_name] == is_common_internal_adrg
		verb = Symbol(ADRG_name * "_dis")
		return is_common_internal_adrg(record, eval(verb), ADRG_name)

	# 特殊ADRG入组, 主诊断+主手术入组
	elseif adrg_func_dict[ADRG_name] == is_both_mdis_and_mopt_adrg
		verb_opt = Symbol(ADRG_name * "_opt")
		verb_dis = Symbol(ADRG_name * "_dis")
		return is_both_mdis_and_mopt_adrg(record, eval(verb_dis), eval(verb_opt), ADRG_name)

	# 特殊ADRG入组, 主诊断+手术(两个)入组
	elseif adrg_func_dict[ADRG_name] == is_both_mdis_and_opt_adrg
		verb_opt1 = Symbol(ADRG_name * "_opt1")
		verb_opt2 = Symbol(ADRG_name * "_opt2")
		verb_dis = Symbol(ADRG_name * "_dis")
		return is_both_mdis_and_opt_adrg(record, eval(verb_dis), eval(verb_opt1), eval(verb_opt2), ADRG_name)

	# 特殊ADRG入组, 同时满足的两个手术
	elseif adrg_func_dict[ADRG_name] == is_both_opt_adrg
		verb_opt1 = Symbol(ADRG_name * "_opt1")
		verb_opt2 = Symbol(ADRG_name * "_opt2")
		return is_both_opt_adrg(record, eval(verb_opt1), eval(verb_opt2), ADRG_name)

	# 特殊ADRG入组, 主诊断或其他诊断入组
	elseif adrg_func_dict[ADRG_name] == is_dis_adrg
		verb_dis = Symbol(ADRG_name * "_dis")
		return is_dis_adrg(record, eval(verb_dis), ADRG_name)

	# 特殊入组的ADRG => 主诊断+手术表1，或主诊断+手术表1+手术表3+手术表4
	elseif adrg_func_dict[ADRG_name] == is_mdis_and_multi_surgery_adrg_one
		verb_dis = Symbol(ADRG_name * "_dis")
		verb_opt1 = Symbol(ADRG_name * "_opt1")
		verb_opt2 = Symbol(ADRG_name * "_opt2")
		verb_opt3 = Symbol(ADRG_name * "_opt3")
		verb_opt4 = Symbol(ADRG_name * "_opt4")
		return is_mdis_and_multi_surgery_adrg_one(record, eval(verb_dis), eval(verb_opt1), eval(verb_opt2),eval(verb_opt3), eval(verb_opt4), ADRG_name)

	# 特殊入组的ADRG => 主诊断+手术表1，或主诊断+手术表2+手术表3
	elseif adrg_func_dict[ADRG_name] == is_mdis_and_multi_surgery_adrg_two
		verb_dis = Symbol(ADRG_name * "_dis")
		verb_opt1 = Symbol(ADRG_name * "_opt1")
		verb_opt2 = Symbol(ADRG_name * "_opt2")
		verb_opt3 = Symbol(ADRG_name * "_opt3")
		return is_mdis_and_multi_surgery_adrg_two(record, eval(verb_dis), eval(verb_opt1), eval(verb_opt2),eval(verb_opt3), ADRG_name)

	# 特殊入组的ADRG => 包含全部手术组
	elseif adrg_func_dict[ADRG_name] == is_all_surgery
		return is_all_surgery(record, eval(:all_surgery_list), ADRG_name)

	# 特殊入组的ADRG => 无手术
	elseif adrg_func_dict[ADRG_name] == is_without_surgery
		return is_without_surgery(record, eval(:all_surgery_list), ADRG_name)

	# 特殊入组的ADRG => 不包含WB1手术
	elseif adrg_func_dict[ADRG_name] == is_no_WB1_surgery
		return is_no_WB1_surgery(record, eval(:WB1_opt), ADRG_name)	

	else
		return "KBBZ"
	end

end


# 记录
#=
✔包含以下主要手术或操作：
✔同时包含以下手术：
✔包含以下主要诊断，包含以下主要手术或操作：
✔包含以下主要诊断：
✔包含以下主要诊断，同时包含以下手术:
✔包含以下主要诊断+手术表1+手术表2 或 包含以下主要诊断+手术表1+手术表3+手术表4
✔包含以下主要诊断+手术表1 或 包含以下主要诊断+手术表2+手术表3
✔主要诊断或其他诊断中包含以下诊断：
✔全部手术
✔除WB1外手术
✔包含全部手术
✔符合MDCZ主诊表，且无手术
=#


# MDC下面的ADRG===============================================================
const mdc_map_adrg = Dict(
	"MDCA" => ["AA1","AB1","AC1","AD1","AE1","AF1","AG1","AG2","AH1"],
	"MDCB" => ["BB1","BB2","BC1","BC2","BD1","BD2","BE1","BE2","BJ1","BL1","BM1","BR1","BR2","BS1","BT1","BT2","BU1","BU2","BU3","BV1","BV2","BV3","BW1","BW2","BX1","BX2","BY1","BY2","BZ1"],
	"MDCC" => ["CB1","CB2","CB3","CB4","CC1","CD1","CD2","CJ1","CR1","CS1","CT1","CU1","CV1","CW1","CX1","CZ1"],
	"MDCD" => ["DA1","DB1","DB2","DB3","DC1","DC2","DD1","DD2","DE1","DE2","DG1","DG2","DJ1","DK1","DR1","DS1","DT1","DT2","DU1","DV1","DW1","DZ1"],
	"MDCE" => ["EB1","EB2","EC1","EC2","ED1","EJ1","ER1","ER2","ER3","ES1","ES2","ES3","ET1","ET2","EU1","EV1","EW1","EX1","EX2","EZ1"],
	"MDCF" => ["FB1","FB2","FC1","FD1","FD2","FD3","FE1","FE2","FF1","FF2","FF3","FJ1","FK1","FK2","FK3","FL1","FL2","FL3","FM1","FM2","FM3","FM4","FN1","FN2","FP1","FR1","FR2","FR3","FR4","FT1","FT2","FT3","FT4","FU1","FU2","FV1","FV2","FV3","FW1","FW2","FZ1"],
	"MDCG" => ["GB1","GB2","GC1","GC2","GD1","GD2","GE1","GE2","GF1","GF2","GG1","GJ1","GK1","GK2","GK3","GR1","GS1","GT1","GU1","GU2","GV1","GW1","GZ1"],
	"MDCH" => ["HB1","HC1","HC2","HC3","HJ1","HK1","HL1","HL2","HR1","HS1","HS2","HS3","HT1","HT2","HU1","HZ1","HZ2","HZ3"],
	"MDCI" => ["IB1","IB2","IB3","IC1","IC2","IC3","IC4","ID1","IE1","IF1","IF2","IF3","IF4","IF5","IG1","IH1","IJ1","IR1","IR2","IS1","IS2","IT1","IT2","IT3","IU1","IU2","IU3","IV1","IZ1","IZ2"],
	"MDCJ" => ["JA1","JA2","JB1","JB2","JB3","JC1","JD1","JD2","JJ1","JR1","JR2","JS1","JS2","JT1","JU1","JV1","JV2","JZ1"],
	"MDCK" => ["KB1","KC1","KD1","KD2","KE1","KJ1","KR1","KS1","KT1","KU1","KV1","KZ1"],
	"MDCL" => ["LA1","LA2","LB1","LB2","LC1","LD1","LE1","LF1","LJ1","LL1","LR1","LS1","LT1","LU1","LV1","LW1","LX1","LZ1"],
	"MDCM" => ["MA1","MB1","MC1","MD1","MJ1","MR1","MS1","MZ1"],
	"MDCN" => ["NA1","NA2","NB1","NC1","ND1","NE1","NF1","NG1","NJ1","NR1","NS1","NZ1"],
	"MDCO" => ["OB1","OC1","OD1","OD2","OE1","OF1","OF2","OJ1","OR1","OS1","OS2","OT1","OZ1"],
	"MDCP" => ["PB1","PC1","PJ1","PK1","PR1","PS1","PS2","PS3","PS4","PU1","PV1"],
	"MDCQ" => ["QB1","QJ1","QR1","QS1","QS2","QS3","QS4","QT1"],
	"MDCR" => ["RA1","RA2","RA3","RA4","RB1","RB2","RC1","RD1","RE1","RG1","RR1","RS1","RS2","RT1","RT2","RU1","RV1","RW1","RW2"],
	"MDCS" => ["SB1","SR1","SS1","ST1","SU1","SV1","SZ1"],
	"MDCT" => ["TB1","TR1","TR2","TS1","TS2","TT1","TT2","TU1","TV1","TW1"],
	"MDCU" => ["UR1","US1"],
	"MDCV" => ["VB1","VC1","VJ1","VR1","VS1","VS2","VT1","VZ1"],
	"MDCW" => ["WB1","WC1","WJ1","WR1","WZ1"],
	"MDCX" => ["XJ1","XR1","XR2","XR3","XS1","XS2","XT1","XT2","XT3"],
	"MDCY" => ["YC1","YR1","YR2"],
	"MDCZ" => ["ZB1","ZC1","ZD1","ZJ1","ZZ1"]
)	


# ADRG入组函数字典=================================================================================
const adrg_func_dict = Dict(
	"AA1" => is_common_surgery_adrg,
	"AB1" => is_common_surgery_adrg,
	"AC1" => is_both_opt_adrg,
	"AD1" => is_common_surgery_adrg,
	"AE1" => is_common_surgery_adrg,
	"AF1" => is_common_surgery_adrg,
	"AG1" => is_common_surgery_adrg,
	"AG2" => is_common_surgery_adrg,
	"AH1" => is_common_surgery_adrg,
	"BB1" => is_both_mdis_and_mopt_adrg,
	"BB2" => is_common_surgery_adrg,
	"BC1" => is_both_mdis_and_mopt_adrg,
	"BC2" => is_common_surgery_adrg,
	"BD1" => is_common_surgery_adrg,
	"BD2" => is_common_surgery_adrg,
	"BE1" => is_common_surgery_adrg,
	"BE2" => is_common_surgery_adrg,
	"BJ1" => is_common_surgery_adrg,
	"BL1" => is_common_surgery_adrg,
	"BM1" => is_common_surgery_adrg,
	"BR1" => is_common_internal_adrg,
	"BR2" => is_common_internal_adrg,
	"BS1" => is_common_internal_adrg,
	"BT1" => is_common_internal_adrg,
	"BT2" => is_common_internal_adrg,
	"BU1" => is_common_internal_adrg,
	"BU2" => is_common_internal_adrg,
	"BU3" => is_common_internal_adrg,
	"BV1" => is_common_internal_adrg,
	"BV2" => is_common_internal_adrg,
	"BV3" => is_common_internal_adrg,
	"BW1" => is_common_internal_adrg,
	"BW2" => is_common_internal_adrg,
	"BX1" => is_common_internal_adrg,
	"BX2" => is_common_internal_adrg,
	"BY1" => is_common_internal_adrg,
	"BY2" => is_common_internal_adrg,
	"BZ1" => is_common_internal_adrg,
	"CB1" => is_common_surgery_adrg,
	"CB2" => is_common_surgery_adrg,
	"CB3" => is_common_surgery_adrg,
	"CB4" => is_common_surgery_adrg,
	"CC1" => is_common_surgery_adrg,
	"CD1" => is_common_surgery_adrg,
	"CD2" => is_common_surgery_adrg,
	"CJ1" => is_common_surgery_adrg,
	"CR1" => is_common_internal_adrg,
	"CS1" => is_common_internal_adrg,
	"CT1" => is_common_internal_adrg,
	"CU1" => is_common_internal_adrg,
	"CV1" => is_common_internal_adrg,
	"CW1" => is_common_internal_adrg,
	"CX1" => is_common_internal_adrg,
	"CZ1" => is_common_internal_adrg,
	"DA1" => is_both_mdis_and_mopt_adrg,
	"DB1" => is_common_surgery_adrg,
	"DB2" => is_common_surgery_adrg,
	"DB3" => is_common_surgery_adrg,
	"DC1" => is_common_surgery_adrg,
	"DC2" => is_common_surgery_adrg,
	"DD1" => is_common_surgery_adrg,
	"DD2" => is_common_surgery_adrg,
	"DE1" => is_common_surgery_adrg,
	"DE2" => is_common_surgery_adrg,
	"DG1" => is_common_surgery_adrg,
	"DG2" => is_common_surgery_adrg,
	"DJ1" => is_common_surgery_adrg,
	"DK1" => is_common_surgery_adrg,
	"DR1" => is_common_internal_adrg,
	"DS1" => is_common_internal_adrg,
	"DT1" => is_common_internal_adrg,
	"DT2" => is_common_internal_adrg,
	"DU1" => is_common_internal_adrg,
	"DV1" => is_common_internal_adrg,
	"DW1" => is_common_internal_adrg,
	"DZ1" => is_common_internal_adrg,
	"EB1" => is_common_surgery_adrg,
	"EB2" => is_common_surgery_adrg,
	"EC1" => is_common_surgery_adrg,
	"EC2" => is_common_surgery_adrg,
	"ED1" => is_common_surgery_adrg,
	"EJ1" => is_common_surgery_adrg,
	"ER1" => is_common_internal_adrg,
	"ER2" => is_common_internal_adrg,
	"ER3" => is_common_internal_adrg,
	"ES1" => is_common_internal_adrg,
	"ES2" => is_common_internal_adrg,
	"ES3" => is_common_internal_adrg,
	"ET1" => is_common_internal_adrg,
	"ET2" => is_common_internal_adrg,
	"EU1" => is_common_internal_adrg,
	"EV1" => is_common_internal_adrg,
	"EW1" => is_common_internal_adrg,
	"EX1" => is_common_internal_adrg,
	"EX2" => is_common_internal_adrg,
	"EZ1" => is_common_internal_adrg,
	"FB1" => is_both_opt_adrg,
	"FB2" => is_common_surgery_adrg,
	"FC1" => is_common_surgery_adrg,
	"FD1" => is_common_surgery_adrg,
	"FD2" => is_common_surgery_adrg,
	"FD3" => is_common_surgery_adrg,
	"FE1" => is_both_opt_adrg,
	"FE2" => is_common_surgery_adrg,
	"FF1" => is_common_surgery_adrg,
	"FF2" => is_both_opt_adrg,
	"FF3" => is_common_surgery_adrg,
	"FJ1" => is_common_surgery_adrg,
	"FK1" => is_both_mdis_and_mopt_adrg,
	"FK2" => is_common_surgery_adrg,
	"FK3" => is_common_surgery_adrg,
	"FL1" => is_both_mdis_and_mopt_adrg,
	"FL2" => is_common_surgery_adrg,
	"FL3" => is_common_surgery_adrg,
	"FM1" => is_common_surgery_adrg,
	"FM2" => is_common_surgery_adrg,
	"FM3" => is_common_surgery_adrg,
	"FM4" => is_common_surgery_adrg,
	"FN1" => is_common_surgery_adrg,
	"FN2" => is_common_surgery_adrg,
	"FP1" => is_both_mdis_and_mopt_adrg,
	"FR1" => is_common_internal_adrg,
	"FR2" => is_common_internal_adrg,
	"FR3" => is_common_internal_adrg,
	"FR4" => is_common_internal_adrg,
	"FT1" => is_common_internal_adrg,
	"FT2" => is_common_internal_adrg,
	"FT3" => is_common_internal_adrg,
	"FT4" => is_common_internal_adrg,
	"FU1" => is_common_internal_adrg,
	"FU2" => is_common_internal_adrg,
	"FV1" => is_common_internal_adrg,
	"FV2" => is_common_internal_adrg,
	"FV3" => is_common_internal_adrg,
	"FW1" => is_common_internal_adrg,
	"FW2" => is_common_internal_adrg,
	"FZ1" => is_common_internal_adrg,
	"GB1" => is_common_surgery_adrg,
	"GB2" => is_common_surgery_adrg,
	"GC1" => is_common_surgery_adrg,
	"GC2" => is_common_surgery_adrg,
	"GD1" => is_both_mdis_and_mopt_adrg,
	"GD2" => is_common_surgery_adrg,
	"GE1" => is_common_surgery_adrg,
	"GE2" => is_common_surgery_adrg,
	"GF1" => is_common_surgery_adrg,
	"GF2" => is_common_surgery_adrg,
	"GG1" => is_common_surgery_adrg,
	"GJ1" => is_common_surgery_adrg,
	"GK1" => is_common_surgery_adrg,
	"GK2" => is_common_surgery_adrg,
	"GK3" => is_common_surgery_adrg,
	"GR1" => is_common_internal_adrg,
	"GS1" => is_common_internal_adrg,
	"GT1" => is_common_internal_adrg,
	"GU1" => is_common_internal_adrg,
	"GU2" => is_common_internal_adrg,
	"GV1" => is_common_internal_adrg,
	"GW1" => is_common_internal_adrg,
	"GZ1" => is_common_internal_adrg,
	"HB1" => is_common_surgery_adrg,
	"HC1" => is_common_surgery_adrg,
	"HC2" => is_common_surgery_adrg,
	"HC3" => is_common_surgery_adrg,
	"HJ1" => is_common_surgery_adrg,
	"HK1" => is_common_surgery_adrg,
	"HL1" => is_common_surgery_adrg,
	"HL2" => is_common_surgery_adrg,
	"HR1" => is_common_internal_adrg,
	"HS1" => is_common_internal_adrg,
	"HS2" => is_common_internal_adrg,
	"HS3" => is_common_internal_adrg,
	"HT1" => is_common_internal_adrg,
	"HT2" => is_common_internal_adrg,
	"HU1" => is_common_internal_adrg,
	"HZ1" => is_common_internal_adrg,
	"HZ2" => is_common_internal_adrg,
	"HZ3" => is_common_internal_adrg,
	"IB1" => is_both_mdis_and_opt_adrg,
	"IB2" => is_common_surgery_adrg,
	"IB3" => is_common_surgery_adrg,
	"IC1" => is_common_surgery_adrg,
	"IC2" => is_common_surgery_adrg,
	"IC3" => is_common_surgery_adrg,
	"IC4" => is_common_surgery_adrg,
	"ID1" => is_common_surgery_adrg,
	"IE1" => is_common_surgery_adrg,
	"IF1" => is_common_surgery_adrg,
	"IF2" => is_common_surgery_adrg,
	"IF3" => is_common_surgery_adrg,
	"IF4" => is_common_surgery_adrg,
	"IF5" => is_common_surgery_adrg,
	"IG1" => is_common_surgery_adrg,
	"IH1" => is_common_surgery_adrg,
	"IJ1" => is_common_surgery_adrg,
	"IR1" => is_common_internal_adrg,
	"IR2" => is_common_internal_adrg,
	"IS1" => is_common_internal_adrg,
	"IS2" => is_common_internal_adrg,
	"IT1" => is_common_internal_adrg,
	"IT2" => is_common_internal_adrg,
	"IT3" => is_common_internal_adrg,
	"IU1" => is_common_internal_adrg,
	"IU2" => is_common_internal_adrg,
	"IU3" => is_common_internal_adrg,
	"IV1" => is_common_internal_adrg,
	"IZ1" => is_common_internal_adrg,
	"IZ2" => is_common_internal_adrg,
	"JA1" => is_mdis_and_multi_surgery_adrg_one,
	"JA2" => is_mdis_and_multi_surgery_adrg_two,
	"JB1" => is_common_surgery_adrg,
	"JB2" => is_common_surgery_adrg,
	"JB3" => is_common_surgery_adrg,
	"JC1" => is_common_surgery_adrg,
	"JD1" => is_common_surgery_adrg,
	"JD2" => is_common_surgery_adrg,
	"JJ1" => is_common_surgery_adrg,
	"JR1" => is_common_internal_adrg,
	"JR2" => is_common_internal_adrg,
	"JS1" => is_common_internal_adrg,
	"JS2" => is_common_internal_adrg,
	"JT1" => is_common_internal_adrg,
	"JU1" => is_common_internal_adrg,
	"JV1" => is_common_internal_adrg,
	"JV2" => is_common_internal_adrg,
	"JZ1" => is_common_internal_adrg,
	"KB1" => is_common_surgery_adrg,
	"KC1" => is_common_surgery_adrg,
	"KD1" => is_common_surgery_adrg,
	"KD2" => is_common_surgery_adrg,
	"KE1" => is_common_surgery_adrg,
	"KJ1" => is_common_surgery_adrg,
	"KR1" => is_common_internal_adrg,
	"KS1" => is_common_internal_adrg,
	"KT1" => is_common_internal_adrg,
	"KU1" => is_common_internal_adrg,
	"KV1" => is_common_internal_adrg,
	"KZ1" => is_common_internal_adrg,
	"LA1" => is_both_mdis_and_mopt_adrg,
	"LA2" => is_both_mdis_and_mopt_adrg,
	"LB1" => is_common_surgery_adrg,
	"LB2" => is_common_surgery_adrg,
	"LC1" => is_common_surgery_adrg,
	"LD1" => is_common_surgery_adrg,
	"LE1" => is_common_surgery_adrg,
	"LF1" => is_common_surgery_adrg,
	"LJ1" => is_common_surgery_adrg,
	"LL1" => is_common_surgery_adrg,
	"LR1" => is_common_internal_adrg,
	"LS1" => is_common_internal_adrg,
	"LT1" => is_common_internal_adrg,
	"LU1" => is_common_internal_adrg,
	"LV1" => is_common_internal_adrg,
	"LW1" => is_common_internal_adrg,
	"LX1" => is_common_internal_adrg,
	"LZ1" => is_common_internal_adrg,
	"MA1" => is_both_mdis_and_mopt_adrg,
	"MB1" => is_common_surgery_adrg,
	"MC1" => is_common_surgery_adrg,
	"MD1" => is_common_surgery_adrg,
	"MJ1" => is_common_surgery_adrg,
	"MR1" => is_common_internal_adrg,
	"MS1" => is_common_internal_adrg,
	"MZ1" => is_common_internal_adrg,
	"NA1" => is_mdis_and_multi_surgery_adrg_two,
	"NA2" => is_both_mdis_and_mopt_adrg,
	"NB1" => is_common_surgery_adrg,
	"NC1" => is_common_surgery_adrg,
	"ND1" => is_common_surgery_adrg,
	"NE1" => is_common_surgery_adrg,
	"NF1" => is_common_surgery_adrg,
	"NG1" => is_both_mdis_and_mopt_adrg,
	"NJ1" => is_common_surgery_adrg,
	"NR1" => is_common_internal_adrg,
	"NS1" => is_common_internal_adrg,
	"NZ1" => is_common_internal_adrg,
	"OB1" => is_common_surgery_adrg,
	"OC1" => is_common_surgery_adrg,
	"OD1" => is_common_surgery_adrg,
	"OD2" => is_common_surgery_adrg,
	"OE1" => is_both_mdis_and_mopt_adrg,
	"OF1" => is_both_mdis_and_mopt_adrg,
	"OF2" => is_both_mdis_and_mopt_adrg,
	"OJ1" => is_common_surgery_adrg,
	"OR1" => is_common_internal_adrg,
	"OS1" => is_common_internal_adrg,
	"OS2" => is_common_internal_adrg,
	"OT1" => is_common_internal_adrg,
	"OZ1" => is_common_internal_adrg,
	"PB1" => is_common_surgery_adrg,
	"PC1" => is_common_surgery_adrg,
	"PJ1" => is_common_surgery_adrg,
	"PK1" => is_common_surgery_adrg,
	"PR1" => is_common_internal_adrg,
	"PS1" => is_dis_adrg,
	"PS2" => is_dis_adrg,
	"PS3" => is_dis_adrg,
	"PS4" => is_dis_adrg,
	"PU1" => is_common_internal_adrg,
	"PV1" => is_common_internal_adrg,
	"QB1" => is_common_surgery_adrg,
	"QJ1" => is_common_surgery_adrg,
	"QR1" => is_common_internal_adrg,
	"QS1" => is_common_internal_adrg,
	"QS2" => is_common_internal_adrg,
	"QS3" => is_common_internal_adrg,
	"QS4" => is_common_internal_adrg,
	"QT1" => is_common_internal_adrg,
	"RA1" => is_both_mdis_and_mopt_adrg,
	"RA2" => is_both_mdis_and_mopt_adrg,
	"RA3" => is_both_mdis_and_mopt_adrg,
	"RA4" => is_both_mdis_and_mopt_adrg,
	"RB1" => is_both_mdis_and_mopt_adrg,
	"RB2" => is_both_mdis_and_mopt_adrg,
	"RC1" => is_both_mdis_and_mopt_adrg,
	"RD1" => is_common_surgery_adrg,
	"RE1" => is_both_mdis_and_mopt_adrg,
	"RG1" => is_both_mdis_and_mopt_adrg,
	"RR1" => is_common_internal_adrg,
	"RS1" => is_common_internal_adrg,
	"RS2" => is_common_internal_adrg,
	"RT1" => is_common_internal_adrg,
	"RT2" => is_common_internal_adrg,
	"RU1" => is_common_internal_adrg,
	"RV1" => is_common_internal_adrg,
	"RW1" => is_common_internal_adrg,
	"RW2" => is_common_internal_adrg,
	"SB1" => is_all_surgery,
	"SR1" => is_common_internal_adrg,
	"SS1" => is_common_internal_adrg,
	"ST1" => is_common_internal_adrg,
	"SU1" => is_common_internal_adrg,
	"SV1" => is_common_internal_adrg,
	"SZ1" => is_common_internal_adrg,
	"TB1" => is_all_surgery,
	"TR1" => is_common_internal_adrg,
	"TR2" => is_common_internal_adrg,
	"TS1" => is_common_internal_adrg,
	"TS2" => is_common_internal_adrg,
	"TT1" => is_common_internal_adrg,
	"TT2" => is_common_internal_adrg,
	"TU1" => is_common_internal_adrg,
	"TV1" => is_common_internal_adrg,
	"TW1" => is_common_internal_adrg,
	"UR1" => is_common_internal_adrg,
	"US1" => is_common_internal_adrg,
	"VB1" => is_common_surgery_adrg,
	"VC1" => is_common_surgery_adrg,
	"VJ1" => is_common_surgery_adrg,
	"VR1" => is_common_internal_adrg,
	"VS1" => is_common_internal_adrg,
	"VS2" => is_common_internal_adrg,
	"VT1" => is_common_internal_adrg,
	"VZ1" => is_common_internal_adrg,
	"WB1" => is_both_mdis_and_mopt_adrg,
	"WC1" => is_common_surgery_adrg,
	"WJ1" => is_no_WB1_surgery,
	"WR1" => is_common_internal_adrg,
	"WZ1" => is_common_internal_adrg,
	"XJ1" => is_all_surgery,
	"XR1" => is_common_internal_adrg,
	"XR2" => is_common_internal_adrg,
	"XR3" => is_common_internal_adrg,
	"XS1" => is_common_internal_adrg,
	"XS2" => is_common_internal_adrg,
	"XT1" => is_common_internal_adrg,
	"XT2" => is_common_internal_adrg,
	"XT3" => is_common_internal_adrg,
	"YC1" => is_all_surgery,
	"YR1" => is_common_internal_adrg,
	"YR2" => is_common_internal_adrg,
	"ZB1" => is_common_surgery_adrg,
	"ZC1" => is_common_surgery_adrg,
	"ZD1" => is_common_surgery_adrg,
	"ZJ1" => is_common_surgery_adrg,
	"ZZ1" => is_without_surgery
)


# ADRG类型(外科、操作、内科)字典
const adrg_type_dict = Dict(
"AA1" => ("外科","无细分"),
"AB1" => ("外科","无细分"),
"AC1" => ("外科","无细分"),
"AD1" => ("外科","无细分"),
"AE1" => ("外科","无细分"),
"AF1" => ("外科","无细分"),
"AG1" => ("外科","无细分"),
"AG2" => ("外科","无细分"),
"AH1" => ("外科","3合并5"),
"BB1" => ("外科","无合并"),
"BB2" => ("外科","无合并"),
"BC1" => ("外科","无细分"),
"BC2" => ("外科","无细分"),
"BD1" => ("外科","无合并"),
"BD2" => ("外科","无细分"),
"BE1" => ("外科","无细分"),
"BE2" => ("外科","无合并"),
"BJ1" => ("外科","无合并"),
"BL1" => ("操作","无合并"),
"BM1" => ("操作","无合并"),
"BR1" => ("内科","1合并3"),
"BR2" => ("内科","无合并"),
"BS1" => ("内科","无合并"),
"BT1" => ("内科","无合并"),
"BT2" => ("内科","无合并"),
"BU1" => ("内科","无合并"),
"BU2" => ("内科","无合并"),
"BU3" => ("内科","无合并"),
"BV1" => ("内科","无合并"),
"BV2" => ("内科","无合并"),
"BV3" => ("内科","无合并"),
"BW1" => ("内科","1合并3"),
"BW2" => ("内科","无合并"),
"BX1" => ("内科","无合并"),
"BX2" => ("内科","无合并"),
"BY1" => ("内科","无合并"),
"BY2" => ("内科","无合并"),
"BZ1" => ("内科","无合并"),
"CB1" => ("外科","无合并"),
"CB2" => ("外科","无细分"),
"CB3" => ("外科","无合并"),
"CB4" => ("外科","1合并3"),
"CC1" => ("外科","1合并3"),
"CD1" => ("外科","无合并"),
"CD2" => ("外科","无合并"),
"CJ1" => ("外科","1合并3"),
"CR1" => ("内科","无细分"),
"CS1" => ("内科","1合并3"),
"CT1" => ("内科","无合并"),
"CU1" => ("内科","无合并"),
"CV1" => ("内科","1合并3"),
"CW1" => ("内科","无细分"),
"CX1" => ("内科","无合并"),
"CZ1" => ("内科","1合并3"),
"DA1" => ("外科","无合并"),
"DB1" => ("外科","无细分"),
"DB2" => ("外科","无细分"),
"DB3" => ("外科","1合并3"),
"DC1" => ("外科","无合并"),
"DC2" => ("外科","1合并3"),
"DD1" => ("外科","无细分"),
"DD2" => ("外科","1合并3"),
"DE1" => ("外科","无合并"),
"DE2" => ("外科","1合并3"),
"DG1" => ("外科","1合并3"),
"DG2" => ("外科","无合并"),
"DJ1" => ("外科","无合并"),
"DK1" => ("操作","无合并"),
"DR1" => ("内科","无合并"),
"DS1" => ("内科","无合并"),
"DT1" => ("内科","1合并3"),
"DT2" => ("内科","1合并3"),
"DU1" => ("内科","无合并"),
"DV1" => ("内科","1合并3"),
"DW1" => ("内科","无合并"),
"DZ1" => ("内科","无合并"),
"EB1" => ("外科","无合并"),
"EB2" => ("外科","无合并"),
"EC1" => ("外科","无合并"),
"EC2" => ("外科","无合并"),
"ED1" => ("外科","无合并"),
"EJ1" => ("外科","无合并"),
"ER1" => ("内科","无合并"),
"ER2" => ("内科","无合并"),
"ER3" => ("内科","3合并5"),
"ES1" => ("内科","无合并"),
"ES2" => ("内科","无合并"),
"ES3" => ("内科","无合并"),
"ET1" => ("内科","无合并"),
"ET2" => ("内科","无合并"),
"EU1" => ("内科","无合并"),
"EV1" => ("内科","无合并"),
"EW1" => ("内科","无合并"),
"EX1" => ("内科","无合并"),
"EX2" => ("内科","无合并"),
"EZ1" => ("内科","无合并"),
"FB1" => ("外科","无细分"),
"FB2" => ("外科","无合并"),
"FC1" => ("外科","无细分"),
"FD1" => ("外科","无合并"),
"FD2" => ("外科","无细分"),
"FD3" => ("外科","1合并3"),
"FE1" => ("外科","无细分"),
"FE2" => ("外科","无细分"),
"FF1" => ("外科","1合并3"),
"FF2" => ("外科","1合并3"),
"FF3" => ("外科","无合并"),
"FJ1" => ("外科","无合并"),
"FK1" => ("操作","无细分"),
"FK2" => ("操作","无细分"),
"FK3" => ("操作","无合并"),
"FL1" => ("操作","无合并"),
"FL2" => ("操作","无合并"),
"FL3" => ("操作","无细分"),
"FM1" => ("操作","无合并"),
"FM2" => ("操作","无合并"),
"FM3" => ("操作","无合并"),
"FM4" => ("操作","无合并"),
"FN1" => ("操作","无细分"),
"FN2" => ("操作","无合并"),
"FP1" => ("操作","3合并5"),
"FR1" => ("内科","无合并"),
"FR2" => ("内科","无合并"),
"FR3" => ("内科","无合并"),
"FR4" => ("内科","无合并"),
"FT1" => ("内科","无合并"),
"FT2" => ("内科","无合并"),
"FT3" => ("内科","无合并"),
"FT4" => ("内科","无合并"),
"FU1" => ("内科","无合并"),
"FU2" => ("内科","无合并"),
"FV1" => ("内科","1合并3"),
"FV2" => ("内科","无合并"),
"FV3" => ("内科","无合并"),
"FW1" => ("内科","无合并"),
"FW2" => ("内科","无合并"),
"FZ1" => ("内科","无合并"),
"GB1" => ("外科","无合并"),
"GB2" => ("外科","无合并"),
"GC1" => ("外科","无合并"),
"GC2" => ("外科","无合并"),
"GD1" => ("外科","无合并"),
"GD2" => ("外科","无合并"),
"GE1" => ("外科","无合并"),
"GE2" => ("外科","无细分"),
"GF1" => ("外科","无合并"),
"GF2" => ("外科","无合并"),
"GG1" => ("外科","无合并"),
"GJ1" => ("外科","无合并"),
"GK1" => ("操作","无合并"),
"GK2" => ("操作","无合并"),
"GK3" => ("操作","无合并"),
"GR1" => ("内科","无合并"),
"GS1" => ("内科","无合并"),
"GT1" => ("内科","无合并"),
"GU1" => ("内科","1合并3"),
"GU2" => ("内科","无合并"),
"GV1" => ("内科","无合并"),
"GW1" => ("内科","1合并3"),
"GZ1" => ("内科","无合并"),
"HB1" => ("外科","无合并"),
"HC1" => ("外科","无合并"),
"HC2" => ("外科","无合并"),
"HC3" => ("外科","无合并"),
"HJ1" => ("外科","无合并"),
"HK1" => ("操作","3合并5"),
"HL1" => ("操作","无合并"),
"HL2" => ("操作","无合并"),
"HR1" => ("内科","无合并"),
"HS1" => ("内科","无合并"),
"HS2" => ("内科","无合并"),
"HS3" => ("内科","无合并"),
"HT1" => ("内科","无合并"),
"HT2" => ("内科","无合并"),
"HU1" => ("内科","无合并"),
"HZ1" => ("内科","无合并"),
"HZ2" => ("内科","无合并"),
"HZ3" => ("内科","无合并"),
"IB1" => ("外科","无细分"),
"IB2" => ("外科","无合并"),
"IB3" => ("外科","无合并"),
"IC1" => ("外科","无细分"),
"IC2" => ("外科","3合并5"),
"IC3" => ("外科","3合并5"),
"IC4" => ("外科","无合并"),
"ID1" => ("外科","无合并"),
"IE1" => ("外科","无合并"),
"IF1" => ("外科","无合并"),
"IF2" => ("外科","无合并"),
"IF3" => ("外科","无合并"),
"IF4" => ("外科","无合并"),
"IF5" => ("外科","无合并"),
"IG1" => ("外科","无合并"),
"IH1" => ("外科","无合并"),
"IJ1" => ("外科","无合并"),
"IR1" => ("内科","无合并"),
"IR2" => ("内科","无合并"),
"IS1" => ("内科","无合并"),
"IS2" => ("内科","无合并"),
"IT1" => ("内科","无合并"),
"IT2" => ("内科","1合并3"),
"IT3" => ("内科","无合并"),
"IU1" => ("内科","无合并"),
"IU2" => ("内科","无合并"),
"IU3" => ("内科","无合并"),
"IV1" => ("内科","1合并3"),
"IZ1" => ("内科","无合并"),
"IZ2" => ("内科","无合并"),
"JA1" => ("外科","无细分"),
"JA2" => ("外科","1合并3"),
"JB1" => ("外科","1合并3"),
"JB2" => ("外科","1合并3"),
"JB3" => ("外科","1合并3"),
"JC1" => ("外科","1合并3"),
"JD1" => ("外科","无合并"),
"JD2" => ("外科","无合并"),
"JJ1" => ("外科","无合并"),
"JR1" => ("内科","无合并"),
"JR2" => ("内科","无合并"),
"JS1" => ("内科","无合并"),
"JS2" => ("内科","无合并"),
"JT1" => ("内科","无合并"),
"JU1" => ("内科","无合并"),
"JV1" => ("内科","1合并3"),
"JV2" => ("内科","1合并3"),
"JZ1" => ("内科","无合并"),
"KB1" => ("外科","无合并"),
"KC1" => ("外科","无细分"),
"KD1" => ("外科","无合并"),
"KD2" => ("外科","无合并"),
"KE1" => ("外科","无细分"),
"KJ1" => ("外科","无合并"),
"KR1" => ("内科","无合并"),
"KS1" => ("内科","无合并"),
"KT1" => ("内科","无合并"),
"KU1" => ("内科","无合并"),
"KV1" => ("内科","无合并"),
"KZ1" => ("内科","无合并"),
"LA1" => ("外科","无合并"),
"LA2" => ("外科","无合并"),
"LB1" => ("外科","无合并"),
"LB2" => ("外科","无合并"),
"LC1" => ("外科","无合并"),
"LD1" => ("外科","无合并"),
"LE1" => ("外科","无合并"),
"LF1" => ("外科","无合并"),
"LJ1" => ("外科","无合并"),
"LL1" => ("操作","无合并"),
"LR1" => ("内科","无合并"),
"LS1" => ("内科","无合并"),
"LT1" => ("内科","无合并"),
"LU1" => ("内科","无合并"),
"LV1" => ("内科","无合并"),
"LW1" => ("内科","无合并"),
"LX1" => ("内科","无合并"),
"LZ1" => ("内科","无合并"),
"MA1" => ("外科","无合并"),
"MB1" => ("外科","无合并"),
"MC1" => ("外科","无合并"),
"MD1" => ("外科","无合并"),
"MJ1" => ("外科","无合并"),
"MR1" => ("内科","无合并"),
"MS1" => ("内科","无合并"),
"MZ1" => ("内科","无合并"),
"NA1" => ("外科","无合并"),
"NA2" => ("外科","无合并"),
"NB1" => ("外科","1合并3"),
"NC1" => ("外科","无合并"),
"ND1" => ("外科","1合并3"),
"NE1" => ("外科","无合并"),
"NF1" => ("外科","无合并"),
"NG1" => ("外科","无细分"),
"NJ1" => ("外科","1合并3"),
"NR1" => ("内科","无合并"),
"NS1" => ("内科","无合并"),
"NZ1" => ("内科","无合并"),
"OB1" => ("外科","无合并"),
"OC1" => ("外科","无合并"),
"OD1" => ("外科","无合并"),
"OD2" => ("外科","1合并3"),
"OE1" => ("外科","无合并"),
"OF1" => ("外科","无细分"),
"OF2" => ("外科","无合并"),
"OJ1" => ("外科","无合并"),
"OR1" => ("内科","无合并"),
"OS1" => ("内科","无合并"),
"OS2" => ("内科","无合并"),
"OT1" => ("内科","无合并"),
"OZ1" => ("内科","无合并"),
"PB1" => ("外科","无细分"),
"PC1" => ("外科","无合并"),
"PJ1" => ("外科","无细分"),
"PK1" => ("操作","无合并"),
"PR1" => ("内科","无合并"),
"PS1" => ("内科","无合并"),
"PS2" => ("内科","无合并"),
"PS3" => ("内科","无合并"),
"PS4" => ("内科","无合并"),
"PU1" => ("内科","无合并"),
"PV1" => ("内科","无合并"),
"QB1" => ("外科","无细分"),
"QJ1" => ("外科","1合并3"),
"QR1" => ("内科","无合并"),
"QS1" => ("内科","无合并"),
"QS2" => ("内科","无合并"),
"QS3" => ("内科","无合并"),
"QS4" => ("内科","无合并"),
"QT1" => ("内科","无合并"),
"RA1" => ("外科","无合并"),
"RA2" => ("外科","无合并"),
"RA3" => ("外科","无合并"),
"RA4" => ("外科","无细分"),
"RB1" => ("外科","无合并"),
"RB2" => ("外科","无合并"),
"RC1" => ("外科","3合并5"),
"RD1" => ("外科","无合并"),
"RE1" => ("外科","无合并"),
"RG1" => ("外科","无合并"),
"RR1" => ("内科","无合并"),
"RS1" => ("内科","无合并"),
"RS2" => ("内科","无合并"),
"RT1" => ("内科","无合并"),
"RT2" => ("内科","无细分"),
"RU1" => ("内科","无合并"),
"RV1" => ("内科","3合并5"),
"RW1" => ("内科","无合并"),
"RW2" => ("内科","无合并"),
"SB1" => ("外科","无合并"),
"SR1" => ("内科","无合并"),
"SS1" => ("内科","无合并"),
"ST1" => ("内科","无合并"),
"SU1" => ("内科","1合并3"),
"SV1" => ("内科","无合并"),
"SZ1" => ("内科","无合并"),
"TB1" => ("外科","无合并"),
"TR1" => ("内科","1合并3"),
"TR2" => ("内科","无细分"),
"TS1" => ("内科","1合并3"),
"TS2" => ("内科","无合并"),
"TT1" => ("内科","1合并3"),
"TT2" => ("内科","1合并3"),
"TU1" => ("内科","无合并"),
"TV1" => ("内科","无合并"),
"TW1" => ("内科","无合并"),
"UR1" => ("内科","1合并3"),
"US1" => ("内科","无细分"),
"VB1" => ("外科","无合并"),
"VC1" => ("外科","无合并"),
"VJ1" => ("外科","无合并"),
"VR1" => ("内科","无合并"),
"VS1" => ("内科","无合并"),
"VS2" => ("内科","无合并"),
"VT1" => ("内科","无合并"),
"VZ1" => ("内科","无合并"),
"WB1" => ("外科","3合并5"),
"WC1" => ("外科","3合并5"),
"WJ1" => ("外科","无合并"),
"WR1" => ("内科","无合并"),
"WZ1" => ("内科","无合并"),
"XJ1" => ("外科","无合并"),
"XR1" => ("内科","无合并"),
"XR2" => ("内科","无合并"),
"XR3" => ("内科","1合并3"),
"XS1" => ("内科","无合并"),
"XS2" => ("内科","无合并"),
"XT1" => ("内科","1合并3"),
"XT2" => ("内科","无细分"),
"XT3" => ("内科","无合并"),
"YC1" => ("外科","无合并"),
"YR1" => ("内科","无合并"),
"YR2" => ("内科","无合并"),
"ZB1" => ("外科","无细分"),
"ZC1" => ("外科","无合并"),
"ZD1" => ("外科","3合并5"),
"ZJ1" => ("外科","3合并5"),
"ZZ1" => ("内科","无合并")
)





