# Create and Consume

Ratio Native helps a person notice the balance between making things and taking things in during their computer use.

## Language

**Activity source**: An application or website to which foreground time is attributed.
_Avoid_: task, session

**Category**: A person's remembered choice of Create or Consume for an activity source.
_Avoid_: productivity score

**Unclassified activity**: Foreground time belonging to an activity source without a category. It is visible in totals but excluded from the ratio.
_Avoid_: neutral category

**Ratio**: The percentage of classified time spent creating compared with consuming. It is undefined when no classified time exists.
_Avoid_: score

**Tracked time**: Foreground time counted while tracking is active, including the idle grace period and unclassified activity.

**Excluded application**: An application that accrues no new tracked time while it is foreground. Existing history remains available, and time in an excluded application does not count toward the previous activity source.

**Day**: The local calendar date to which tracked time was assigned when it occurred.

**Idle grace**: The first five minutes without input, which still count as tracked time to accommodate reading.

**Demo**: An isolated, fictional activity dataset used to learn the interface without changing real activity.
