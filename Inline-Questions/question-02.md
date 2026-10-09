## MetaData
Question Type : Single Choice

## Question
2. Why are the external IP address and TCP/22 firewall rule required for the selected `gcloud compute ssh` workflow from `labvm`?

## Options
Option 1 : The external IP selects the Ubuntu image, and TCP/22 determines the VM machine type.

Option 2 : The external IP provides a reachable destination from `labvm`, and the TCP/22 rule permits SSH traffic to the VM.

Option 3 : The external IP assigns the VM to the required subnet, and TCP/22 enables HTTP access to the Google Cloud console.

Option 4 : The external IP creates the SSH key, and the TCP/22 rule starts the VM automatically.

## Answers
Option 2 : 2

## Correct Answer Feedback
Option 2 is correct answer, because `gcloud compute ssh` needs a reachable VM address and permitted SSH traffic on TCP port 22.

## Incorrect Answer Feedback
Selected option is not correct. Option 2 is the correct answer.

## Number of Retries
1
