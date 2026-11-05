| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 29/50 | 31/50 | 34/50 |
| correct (complex) | 27/45 | 29/45 | 32/45 |
| correct (simple) | 2/5 | 2/5 | 2/5 |
| wrong but accepted | 21 | 11 | 9 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 8 | 7 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 29/50 | 31/50 | 34/50 |
| cell accuracy, answered | 0.945 | 0.968 | 0.971 |
| cell accuracy, end to end | 0.945 | 0.813 | 0.835 |
| model calls | 50 | 50 | 50 |
| input tokens | 349,610 | 349,610 | 338,986 |
| output tokens | 31,996 | 32,310 | 34,635 |
| input tokens per table | 6,992 | 6,992 | 6,780 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC12914422/t0 | complex/subtables | correct (1.00), 9,887 in | correct (1.00), 9,887 in | correct (1.00), 9,619 in |
| PMC12688826/t3 | complex/separator_rows | correct (1.00), 4,437 in | correct (1.00), 4,437 in | correct (1.00), 4,247 in |
| PMC7555252/t0 | complex/multi_level | wrong_accepted (0.42), 11,731 in | rejected, 11,731 in | rejected, 11,463 in |
| PMC12434915/t0 | complex/subtables | wrong_accepted (0.98), 8,267 in | rejected, 8,267 in | correct (1.00), 8,111 in |
| PMC9822893/t6 | complex/separator_rows | correct (1.00), 5,145 in | correct (1.00), 5,145 in | correct (1.00), 4,999 in |
| PMC12632427/t0 | simple/simple | wrong_accepted (0.87), 3,243 in | wrong_accepted (0.87), 3,243 in | wrong_accepted (0.87), 2,975 in |
| PMC9656733/t1 | simple/simple | wrong_accepted (0.85), 4,211 in | wrong_accepted (0.85), 4,211 in | wrong_accepted (0.85), 3,943 in |
| PMC13190168/t5 | simple/simple | correct (1.00), 11,285 in | correct (1.00), 11,285 in | correct (1.00), 11,017 in |
| PMC1361785/t0 | simple/simple | correct (1.00), 4,171 in | correct (1.00), 4,171 in | correct (1.00), 3,903 in |
| PMC10199865/t2 | simple/simple | wrong_accepted (0.84), 40,201 in | wrong_accepted (0.84), 40,201 in | wrong_accepted (0.84), 39,933 in |
| PMC13096635/t0 | complex/multi_level | wrong_accepted (0.88), 8,139 in | rejected, 8,139 in | correct (1.00), 7,871 in |
| PMC11859888/t1 | complex/multi_level | wrong_accepted (0.82), 4,027 in | wrong_accepted (0.82), 4,027 in | wrong_accepted (0.82), 3,759 in |
| PMC12854148/t0 | complex/multi_level | correct (1.00), 4,703 in | correct (1.00), 4,703 in | correct (1.00), 4,435 in |
| PMC5387038/t5 | complex/subtables | wrong_accepted (0.87), 6,091 in | wrong_accepted (0.87), 6,091 in | wrong_accepted (0.87), 5,923 in |
| PMC10694873/t3 | complex/separator_rows | wrong_accepted (0.94), 9,077 in | correct (1.00), 9,077 in | correct (1.00), 8,951 in |
| PMC8453916/t3 | complex/subtables | correct (1.00), 3,937 in | correct (1.00), 3,937 in | correct (1.00), 3,669 in |
| PMC13015447/t0 | complex/separator_rows | correct (1.00), 3,421 in | correct (1.00), 3,421 in | correct (1.00), 3,227 in |
| PMC12518418/t1 | complex/multi_level | correct (1.00), 4,703 in | correct (1.00), 4,703 in | correct (1.00), 4,435 in |
| PMC5387038/t7 | complex/subtables | wrong_accepted (0.88), 10,179 in | wrong_accepted (0.88), 10,179 in | wrong_accepted (0.88), 9,911 in |
| PMC8407250/t4 | complex/separator_rows | wrong_accepted (0.92), 5,629 in | wrong_accepted (0.92), 5,629 in | wrong_accepted (0.92), 5,443 in |
| PMC5829520/t1 | complex/multi_level | wrong_accepted (0.61), 9,673 in | rejected, 9,673 in | rejected, 9,405 in |
| PMC12688826/t1 | complex/subtables | correct (1.00), 8,399 in | correct (1.00), 8,399 in | correct (1.00), 8,337 in |
| PMC11489153/t0 | complex/separator_rows | wrong_accepted (0.98), 5,975 in | rejected, 5,975 in | rejected, 5,969 in |
| PMC12044418/t1 | complex/multi_level | correct (1.00), 5,207 in | correct (1.00), 5,207 in | correct (1.00), 4,939 in |
| PMC10470671/t0 | complex/subtables | correct (1.00), 6,921 in | correct (1.00), 6,921 in | correct (1.00), 6,763 in |
| PMC5815492/t2 | complex/separator_rows | wrong_accepted (0.95), 4,609 in | wrong_accepted (0.95), 4,609 in | rejected, 4,423 in |
| PMC9661877/t5 | complex/multi_level | correct (1.00), 4,451 in | correct (1.00), 4,451 in | correct (1.00), 4,183 in |
| PMC11651604/t2 | complex/subtables | correct (1.00), 7,511 in | correct (1.00), 7,511 in | wrong_accepted (0.86), 7,311 in |
| PMC11484257/t1 | complex/separator_rows | correct (1.00), 4,365 in | correct (1.00), 4,365 in | correct (1.00), 4,175 in |
| PMC6023111/t5 | complex/multi_level | correct (1.00), 9,669 in | correct (1.00), 9,669 in | correct (1.00), 9,401 in |
| PMC7018020/t5 | complex/subtables | correct (1.00), 4,619 in | correct (1.00), 4,619 in | correct (1.00), 4,351 in |
| PMC7113237/t0 | complex/separator_rows | correct (1.00), 5,131 in | correct (1.00), 5,131 in | correct (1.00), 5,033 in |
| PMC8132967/t1 | complex/multi_level | correct (1.00), 6,483 in | correct (1.00), 6,483 in | correct (1.00), 6,215 in |
| PMC8099387/t1 | complex/subtables | wrong_accepted (0.96), 9,801 in | wrong_accepted (0.96), 9,801 in | rejected, 9,533 in |
| PMC8915277/t1 | complex/separator_rows | correct (1.00), 4,875 in | correct (1.00), 4,875 in | correct (1.00), 4,717 in |
| PMC11397705/t0 | complex/multi_level | correct (1.00), 3,911 in | correct (1.00), 3,911 in | correct (1.00), 3,643 in |
| PMC3465856/t0 | complex/subtables | wrong_accepted (0.95), 8,473 in | rejected, 8,473 in | correct (1.00), 8,297 in |
| PMC5496892/t3 | complex/separator_rows | correct (1.00), 4,261 in | correct (1.00), 4,261 in | correct (1.00), 4,083 in |
| PMC11991517/t2 | complex/multi_level | correct (1.00), 4,041 in | correct (1.00), 4,041 in | correct (1.00), 3,773 in |
| PMC5387038/t2 | complex/subtables | wrong_accepted (0.87), 7,583 in | wrong_accepted (0.87), 7,583 in | wrong_accepted (0.87), 7,419 in |
| PMC13384529/t1 | complex/subtables | wrong_accepted (0.89), 4,709 in | correct (1.00), 4,709 in | correct (1.00), 4,441 in |
| PMC12487654/t2 | complex/separator_rows | correct (1.00), 5,557 in | correct (1.00), 5,557 in | correct (1.00), 5,459 in |
| PMC4802489/t5 | complex/multi_level | correct (1.00), 7,081 in | correct (1.00), 7,081 in | correct (1.00), 6,813 in |
| PMC5720689/t0 | complex/subtables | correct (1.00), 7,557 in | correct (1.00), 7,557 in | correct (1.00), 7,289 in |
| PMC11489153/t1 | complex/separator_rows | wrong_accepted (0.98), 7,471 in | rejected, 7,471 in | rejected, 7,465 in |
| PMC4476672/t1 | complex/multi_level | correct (1.00), 3,967 in | correct (1.00), 3,967 in | correct (1.00), 3,699 in |
| PMC4468928/t9 | complex/subtables | wrong_accepted (0.83), 4,217 in | rejected, 4,217 in | rejected, 4,049 in |
| PMC11651604/t0 | complex/separator_rows | wrong_accepted (0.95), 7,925 in | wrong_accepted (0.82), 7,925 in | correct (1.00), 7,725 in |
| PMC12357927/t2 | complex/multi_level | correct (1.00), 6,119 in | correct (1.00), 6,119 in | correct (1.00), 5,851 in |
| PMC11077913/t2 | complex/subtables | correct (1.00), 6,565 in | correct (1.00), 6,565 in | correct (1.00), 6,391 in |
