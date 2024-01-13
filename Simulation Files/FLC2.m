%{
===========================================================================
- Author:       Ariel Ruiz-Garcia                                         -
- Module:       M28COM Evolutionary and Fuzzy Systems                     -
- Date:         03-Nov-2016                                               -
- Description:  This is a sample program that creates a remote API server -
-               to allow running Matlab code with V-Rep. Morevoer, this   -
-               example implements a Fuzzy Logic Controller for a P3DX    -
-               robot. The FLC takes 3 inputs (ultrasonic sensor readings)-
-               and outputs 2 values (speed for left and right wheels of  -
-               the robot).                                               -
- Requirements:                                                           -
-   1) The files in the "\remoteApiBindings\lib\lib\64Bit" and            -
-      "remoteApiBindings\matlab" folders of your VREP installation folder-
-      must be copied and copied into the same folder as this script. In  -
-      my case these are found at:                                        -
-                                                                         -
-          "C:\Program Files(x86)\V-REP3\V-REP_PRO_EDU\programming\       -
-           remoteApiBindings\matlab\matlab"                              -
-                                                                         -
-          "C:\Program Files (x86)\V-REP3\V-REP_PRO_EDU\programming\      -
-           remoteApiBindings\lib\lib\64Bit"                              -
-                                                                         -
-    2) The following code must be placed in a child cript in the V-Rep   -
-        simulation code:                                                 -
-                    simExtRemoteApiStart(19999)    %port number          -
-                                                                         -
-    3) The FLC must be already implemented and saved in the same folder  -
-       as this script.                                                   - 
-                                                                         -
-    4) Use Matlab 64bit version, else copy the 32bit lib file instead.   -
===========================================================================
%}


% matrix to store simulation values
simulation_data = [];

%Create a remote API using the prot file (remoteApiProto.m)
vrep = remApi('remoteApi'); 

%Ensure that all previous connections are closed
vrep.simxFinish(-1);

%Start the connection with default IP address and port
clientID = vrep.simxStart('127.0.0.1',19999,true,true,5000,5);

%Check if the connection was successful, exit if not
if (clientID>-1)
    disp('Connected to remote API server');
    %In order to get access to the sensors we need to create handles.
    %The PD3X has 16 ultrasonic sensors, therefore we declare a variable
    %that will store these handles. 
    uSensorHandles = zeros(16,1);
    
    %Each ultrasonic sensor returns 3 values: distance of the object 
    %detected over the X, Y, Z axis of the 3d space. 
    uSensorVals = zeros(16,3);
    
    %Get ultrasonic sensors handles for each sensor
    for i=1:16
        %simxGetObjectHandle returns an error code and the sensor handle,
        %if any. The error code can be used to check if the handle was
        %retrieved successfully (though we assume it is in this case). The
        %method takes the clientID (of the robot), the name of the sensor
        %(all sensors are named Pioneer_p3dx_ultrasonicSensor1(to 16)), and
        %the mode of the call. 
        [errCode, sensorHandle] = vrep.simxGetObjectHandle(clientID, strcat('Pioneer_p3dx_ultrasonicSensor',num2str(i)), vrep.simx_opmode_blocking);  
        uSensorHandles(i) = sensorHandle;

        %Before retrieving sensor values we need to initiallize them. 
        [errorCode,detectionState,detectedPoint,detectedObjectHandle,detectedSurfaceNormalVector] = vrep.simxReadProximitySensor(clientID, sensorHandle, vrep.simx_opmode_oneshot_wait);
    
    end
    
    %Now we create the motor handles to get access to the wheels
    [errCode0, motorLeft]  = vrep.simxGetObjectHandle(clientID, 'Pioneer_p3dx_leftMotor', vrep.simx_opmode_oneshot_wait);
    [errCode1, motorRight] = vrep.simxGetObjectHandle(clientID, 'Pioneer_p3dx_rightMotor', vrep.simx_opmode_oneshot_wait);

    %load the fuzzy logic controller
    fismat = readfis('cw2.fis'); 
    
    %Allow the robot to run for 1000 iterations
    for epoch = 1:1000
        %First, get the sensor readings for all sensors
        for i=1:16
            %Specify what sensor we want to read 
            sensorHandle = uSensorHandles(i);
            %Get the reading
            [errorCode,detectionState,detectedPoint,detectedObjectHandle,detectedSurfaceNormalVector] = vrep.simxReadProximitySensor(clientID, sensorHandle, vrep.simx_opmode_oneshot_wait);
            %Uncomment the next two lines if your ultrasonic sensor mode is
            %not set to ray. (say if we want to use the x,y,z positions)
            %uSensorVals(i, 1) = detectedPoint(1); 
            %uSensorVals(i, 2) = detectedPoint(2); 
            
            %Sometimes when the sensors don't detect anything they will
            %return values < 0.01. For this example(this flc) if no
            %obstacle is found we set the distance to 1 meter, just to let
            %the FLC know that if there is an object it is far away from
            %the robot. The ultrasonic sensors reach is set to 1m. 
            if  detectedPoint(3) < 0.01  
                uSensorVals(i, 3) = 1;
            else
                %Otherwise return the actual sensor reading(>0.01m, <1m )
                uSensorVals(i, 3) = detectedPoint(3);
            end
        end
        %We will use the two (most) front sensors average as input one for
        %the flc. This will detect objects right in front of the robot. 
        flc_input1 = mean([uSensorVals(4,3),uSensorVals(5,3)]);
        %The other two inputs will be from sensors point forward/left
        %forward/right. To detect from the side but still forward. 
        flc_input2 = uSensorVals(7,3);
        flc_input3 = uSensorVals(8,3);

        %Send the inputs to the FLC and it will return two values: the
        %xz\xzx0 for the left(speed(1)) and right(speed(2)) motorS 
        speed = evalfis([flc_input1, flc_input2, flc_input3],fismat)
        disp('1 sensor');
        disp(flc_input1);
        disp('2 sensor');
        disp(flc_input2);
        disp('3 sensor');
        disp(flc_input3);
        
        readings = [flc_input1, flc_input2, flc_input3, speed(1), speed(2)];
        simulation_data = [simulation_data; readings];

        %if we need to pause the communication to allow the robot finish
        %executing a given comman we can achieve this using the following
        %line (not neccessary)
        vrep.simxPauseCommunication(clientID,1);
        %Set the speeed for left and right motors with the values returned
        %by the FLC. The speed gets updated at every epoch. 
        leftVel = vrep.simxSetJointTargetVelocity(clientID, motorLeft, speed(1), vrep.simx_opmode_streaming);
        rightVel = vrep.simxSetJointTargetVelocity(clientID, motorRight, speed(2), vrep.simx_opmode_streaming);
        %Let the robot continue executing commands (not neccessary) 
        vrep.simxPauseCommunication(clientID,0);

    end 
    %Once the simulation has finished, stop robot by setting the speed to 0
    leftVel = vrep.simxSetJointTargetVelocity(clientID, motorLeft, 0, vrep.simx_opmode_streaming);
    rightVel = vrep.simxSetJointTargetVelocity(clientID, motorRight,0, vrep.simx_opmode_streaming);

    %Make sure that the robot recieves the command to stop
    vrep.simxGetPingTime(clientID);

    % Now close the connection to V-REP:	
    vrep.simxFinish(clientID);
%If connection to the robot failed
else
    disp('Failed connecting to remote API server');
end
vrep.delete(); % call the destructor
disp('Program ended');
xlswrite('simulation_data.xlsx', simulation_data);
