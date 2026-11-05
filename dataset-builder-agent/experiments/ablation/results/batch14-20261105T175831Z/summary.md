| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 3/10 | 2/10 | 3/10 |
| correct (complex) | 3/10 | 2/10 | 3/10 |
| correct (simple) | – | – | – |
| wrong but accepted | 6 | 6 | 5 |
| invalid output | 1 | 0 | 0 |
| rejected (unparseable) | 0 | 2 | 2 |
| not reviewed | 0 | 0 | 0 |
| model's own answer correct | 3/10 | 2/10 | 3/10 |
| cell accuracy, answered | 0.874 | 0.950 | 0.945 |
| cell accuracy, end to end | 0.874 | 0.760 | 0.756 |
| model calls | 10 | 10 | 10 |
| input tokens | 56,350 | 56,350 | 54,078 |
| output tokens | 6,854 | 6,888 | 8,578 |
| input tokens per table | 5,635 | 5,635 | 5,408 |

| table | set | llm-only | constraints | full |
|---|---|---|---|---|
| PMC4310929/t6 | complex/separator_rows | wrong_accepted (0.93), 7,161 in | wrong_accepted (0.93), 7,161 in | wrong_accepted (0.93), 6,961 in |
| PMC13627762/t2 | complex/multi_level | wrong_accepted (0.89), 5,669 in | wrong_accepted (0.89), 5,669 in | wrong_accepted (0.89), 5,401 in |
| PMC11132289/t1 | complex/separator_rows | correct (1.00), 3,721 in | wrong_accepted (0.97), 3,721 in | correct (1.00), 3,527 in |
| PMC9661877/t22 | complex/multi_level | wrong_accepted (0.96), 5,417 in | wrong_accepted (0.96), 5,417 in | wrong_accepted (0.96), 5,149 in |
| PMC8407250/t2 | complex/separator_rows | wrong_accepted (0.92), 5,733 in | wrong_accepted (0.92), 5,733 in | wrong_accepted (0.92), 5,547 in |
| PMC8132967/t0 | complex/multi_level | correct (1.00), 4,027 in | correct (1.00), 4,027 in | correct (1.00), 3,759 in |
| PMC4802489/t0 | complex/separator_rows | correct (1.00), 6,893 in | correct (1.00), 6,893 in | correct (1.00), 6,703 in |
| PMC6843367/t4 | complex/multi_level | invalid_output (0.82), 3,903 in | rejected, 3,903 in | wrong_accepted (0.86), 3,635 in |
| PMC7780720/t0 | complex/separator_rows | wrong_accepted (0.88), 8,093 in | wrong_accepted (0.94), 8,093 in | rejected, 7,931 in |
| PMC5815492/t3 | complex/multi_level | wrong_accepted (0.35), 5,733 in | rejected, 5,733 in | rejected, 5,465 in |
