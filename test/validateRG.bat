ECHO OFF
SETLOCAL

IF "%~1"=="" (
    ECHO Usage: %0 subscription-id %1 TargetRG  %2 DesiredStateRG %3
    EXIT /B
    )

	
:: Work
:: ToDo ADD CLI Commands
:: ToDo Create Python ValidateRG
:: ToDo Add Python ValidageRG 

:: Explicitly set the subscription to avoid confusion as to which subscription
:: is active/default
SET SUBSCRIPTION=%1
SET TARGETRG=%2
SET DSRG=%3

ECHO %SUBSCRIPTION%
ECHO %TARGETRG%
ECHO %DSRG%

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Call CLI commands to generate the TargetRG JSON file 

CALL azure config mode arm

CALL azure group show --name %TARGETRG% --subscription %SUBSCRIPTION% --json >  TargetRG.JSON



::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Call Python 'ValidageRG.py' to validate the target RG with the Desired State Configuration

python validateRG.py TargetRG.JSON %DSRG%



goto :eof