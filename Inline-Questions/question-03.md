## MetaData
Question Type : Single Choice

## Question
3. Which path and command sequence creates `scenario2.txt` in the default user’s home directory with the exact required content?

## Options
Option 1 : Create `/scenario2.txt` with `echo "scenario 2 is completed" > /scenario2.txt`.

Option 2 : Create `scenario2.txt` in `/tmp` with `echo "scenario 2 is completed" > /tmp/scenario2.txt`.

Option 3 : Create `/root/scenario2.txt` with `sudo sh -c 'echo "scenario 2 is completed" > /root/scenario2.txt'`.

Option 4 : Create `$HOME/scenario2.txt` with `printf 'scenario 2 is completed\n' > "$HOME/scenario2.txt"`.

## Answers
Option 4 : 2

## Correct Answer Feedback
Option 4 is correct because it writes the exact required text, including a normal line ending, to the default user’s home directory without hard-coding a username.

## Incorrect Answer Feedback
Selected option is not correct. Option 4 is the correct answer.

## Number of Retries
1
