| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 6/10 | 6/10 | 8/10 |
| correct (complex) | 6/10 | 6/10 | 8/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 4 | 1 | 1 |
| invalid output | 0 | 0 | 0 |
| rejected (unparseable) | 0 | 3 | 1 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 6/10 | 6/10 | 8/10 |
| cell accuracy, answered | 0.955 | 0.988 | 0.991 |
| cell accuracy, end to end | 0.955 | 0.692 | 0.892 |
| model calls | 10 | 10 | 10 |
| input tokens | 76,124 | 76,124 | 74,262 |
| output tokens | 7,655 | 7,820 | 6,948 |
| input tokens per table | 7,612 | 7,612 | 7,426 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC11704328/t3 | complex/separator_rows | correct (1.00), 5,147 in | correct (1.00), 5,147 in | correct (1.00), 5,053 in |
| PMC6904686/t2 | complex/multi_level | correct (1.00), 3,823 in | correct (1.00), 3,823 in | correct (1.00), 3,555 in |
| PMC12487654/t1 | complex/separator_rows | correct (1.00), 9,741 in | correct (1.00), 9,741 in | correct (1.00), 9,631 in |
| PMC10152309/t1 | complex/multi_level | wrong_accepted (0.81), 8,601 in | correct (1.00), 8,601 in | correct (1.00), 8,333 in |
| PMC10470671/t2 | complex/separator_rows | wrong_accepted (0.95), 8,087 in | rejected, 8,087 in | correct (1.00), 8,009 in |
| PMC8987291/t3 | complex/multi_level | wrong_accepted (0.87), 4,849 in | rejected, 4,849 in | rejected, 4,581 in |
| PMC7911108/t0 | complex/separator_rows | wrong_accepted (0.92), 13,401 in | wrong_accepted (0.92), 13,401 in | wrong_accepted (0.92), 13,267 in |
| PMC4030731/t2 | complex/multi_level | correct (1.00), 10,097 in | rejected, 10,097 in | correct (1.00), 9,829 in |
| PMC10754813/t1 | complex/separator_rows | correct (1.00), 7,993 in | correct (1.00), 7,993 in | correct (1.00), 7,887 in |
| PMC11596707/t3 | complex/multi_level | correct (1.00), 4,385 in | correct (1.00), 4,385 in | correct (1.00), 4,117 in |
