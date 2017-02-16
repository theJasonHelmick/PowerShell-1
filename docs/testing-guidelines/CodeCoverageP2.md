# Code Coverage - Part 2   

In my [last post on code coverage](https://blogs.msdn.microsoft.com/powershell/2017/01/11/code-coverage-now-available-for-powershell-core/), I shared the process for you to collect coverage for your environment. 
This week, I’ll be describing a way to use our tools to create new tests and show how you can measure the increase of coverage for PowerShell Core after adding new tests. 
To recap, we can collect code coverage with the OpenCover module, and then inspect the coverage. 
In this case I would like to know about coverage for a specific cmdlet. 
For this post, we’re going to focus on the Clear-Content Cmdlet because coverage is ok, but not fantastic and it is small enough to go over easily.

Here’s a partial capture from running the OpenCover tools:

![Coverage 2a](Images/coverage-2a.jpg)

By selecting the class Microsoft.PowerShell.Commands.ClearContentCommand we can drill into the specifics about that class which implements the Clear-Content cmdlet. 
We can see that we have about 47% line coverage for this class which isn’t fantastic, by inspecting the red-highlights we can see what’s missing.

![Coverage 2b](Images/coverage-2b.jpg)

![Coverage 2c](Images/coverage-2c.jpg)

![Coverage 2d](Images/coverage-2d.jpg)

It looks like there are some error conditions, and some code which represents whether the underlying provider supports should process are not being tested. 
We can create tests for these missing areas fairly easily, but I need to know where these new tests should go.

## Test Code Layout

Now is a good time to describe how our tests are laid out.

[https://github.com/PowerShell/PowerShell/test](https://github.com/PowerShell/PowerShell/test) 
contains all of the test code for PowerShell. 
This includes our native tests, C-Sharp tests and Pester tests as well as the tools we use. 
Our Pester tests should all be found in 
[https://github.com/PowerShell/PowerShell/test/powershell](https://github.com/PowerShell/PowerShell/test/powershell)
and in that directory there is more structure to make it easier to find tests. 
For example, if you want to find those tests for a specific cmdlet, you would look in the appropriate module directory for those tests. 
In our case, we’re adding tests for Clear-Content, which should be found in [https://github.com/PowerShell/PowerShell/test/powershell/Modules/Microsoft.PowerShell.Management](https://github.com/PowerShell/PowerShell/test/powershell/Modules/Microsoft.PowerShell.Management). 
(You can always find which module a cmdlet resides via get-command). 
If we look in this directory, we can already see the file Clear-Content.Tests.ps1, so we’ll add our tests to that file. 
If that file didn’t exist, you should just create a new file for your tests. 
Sometimes the tests for a cmdlet may be combined with other tests. 
Take this as an opportunity to split up the file to make it easier for the next person adding tests. 
If you want more information about how we segment our tests, you can review [https://github.com/PowerShell/PowerShell/docs/testing-guidelines/testing-guidelines.md](https://github.com/PowerShell/PowerShell/docs/testing-guidelines/testing-guidelines.md).

## New Test Code

Based on the missing code coverage, I created the following replacement for Clear-Content.Tests.ps1 which you can see in this PR: [https://github.com/PowerShell/PowerShell/pull/3157](https://github.com/PowerShell/PowerShell/pull/3157). 
After rerunning the code coverage tools, I can see that I’ve really improved coverage for this cmdlet.

![Coverage 2e](Images/coverage-2e.jpg)

There seems to be a small issue with OpenCover as some close braces are not being marked as missed, but you can see the improvement:

![Coverage 2f](Images/coverage-2f.jpg)

Now it’s your turn and we could really use your help. 
If you have areas of the product that you rely on, and don’t have the tests that you think they should have, please consider adding tests!
