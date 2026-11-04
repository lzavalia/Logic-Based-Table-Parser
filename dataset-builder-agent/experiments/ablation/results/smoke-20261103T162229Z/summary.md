| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 6/15 | 7/15 | 9/15 |
| correct (complex) | 4/10 | 5/10 | 7/10 |
| correct (simple) | 2/5 | 2/5 | 2/5 |
| wrong but accepted | 9 | 5 | 5 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 3 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 6/15 | 7/15 | 9/15 |
| cell accuracy, answered | 0.898 | 0.937 | 0.946 |
| cell accuracy, end to end | 0.898 | 0.750 | 0.883 |
| model calls | 15 | 15 | 15 |
| input tokens | 134,615 | 134,615 | 131,149 |
| output tokens | 8,757 | 9,026 | 8,122 |
| input tokens per table | 8,974 | 8,974 | 8,743 |

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
