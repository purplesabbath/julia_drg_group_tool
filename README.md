# julia_drg_group_tool
DRG分组器Julia版本

## 介绍
使用Julia语言制作的简易分组器, 采用国家1.1分组方案, 使用医保版ICD10诊断编码与IDC9手术操作编码, 细分组部分采用广西的分组方案总共984个DRG组
> 使用Julia语言只为快速完成分组器的分组全流程，对其中的一些算法还有整体结构并没有做太多的打磨，整体上代码重复的片段较多，运行效率也比较差
> 为了图省事直接把分组方案给写进代码里了🤕

## 数据要求
- 病例ID: 结算流水号
- 主诊断编码(必填)
- 主手术编码(手术或操作病例则必填)
- 其他诊断编码(向量)
- 其他手术编码(向量)
- 性别(男 => 1, 女 => 0)
- 年龄(小于1岁, 为小数, 否则为整数)
- 体重(克g)

## 使用方法
运行drg_group.jl文件，可以单个病例分组也可以通过表格进行分组
