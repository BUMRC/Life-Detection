port = "/dev/cu.usbmodem1401"; % change every time
baud = 115200; %also adjust

s = serialport(port, baud);
configureTerminator(s,"LF");
pause(2);
flush(s);

disp('Starting continuous read... Press Ctrl+C to stop.');

while true
    try
        % Read a line from Arduino
        line = readline(s);
        data = str2double(split(line, ","));
        
        % Print or use the data
        fprintf('Received: ');
        fprintf('%g ', data);
        fprintf('\n');
        
    catch ME
        % Catch errors so loop doesn't crash
        warning('Error reading data: %s', ME.message);
    end
end
