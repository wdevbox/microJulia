#microJulia - a simulated microcontroller in Julia meant to feel similar to MicroPython or Arduino's C(++)
#Blake Nemeth - Programming Languages - CIS 3030

#----------------BEGIN SYSTEM SETUP-------------------------
#STRUCTS

#start by defining what a pin_type is - input, output, undefined
#this is actually a macro for creating a subtype of ENUM with objects that can be converted to numbers... but the macro makes it more C style!
@enum pin_type begin
	undefined = -1
	input = 0
	output = 1
end

#julia uses composite types instead of traditional objects/classes/structs. Methods for these are defined /outside/ the related struct.
#structs are immutable by default in julia.
#they can be forced mutable by adding the mutable keyword
#pin can have a type and a data - type being in/out/undefined, data being the state at that moment

mutable struct pin
	type::pin_type
	state::UInt8 #technically should be a bool but Julia actually has bool as a subtype of Int that still requires 8 bits, unsigned because the state can't be negative
end

#IN JULIA, ARRAYS START AT 1
#MCU INITIALIZATION, PART OF THE STRUCTURE THAT MAKES THIS WORK
#a "gpio" state data structure containing all pins (using the enumerated pin type) - probably an array.
#start with all undefined.
#some sort of structure for defining which pins are outputs or inputs - enumerated pin type

num_pins = 16 #an mcu with 16 gpio pins
mcu_pins = Array{pin}(undef, num_pins) #make an empty array filled with undefineds
for counter = 1:(num_pins)
	mcu_pins[counter] = pin(undefined, 0) #init all pins to undefined to begin with
end

#FUNCTION DEFINITIONS
#digitalWrite - check if supplied input is an output pin, if so, set it to the supplied value. If not, return -1.

function digitalWrite(x::pin, data::Int64) #this does work, it modifies the original variable. hooray
	#check if the pin is a digital out...
	if(x.type == output)
		x.state = data
		return data #return the data back so it can be printed/used for debugging purposes
	else
		return -1 #return -1 because pin wasn't an output, not a valid action
	end
end

function digitalWrite(x::Int, data::Int64) #for writing to a specific pin by index instead of by reference
	#check if valid index and pass through to other one with pin object from the array
	if(x > 0 && x <= num_pins)
		digitalWrite(mcu_pins[x],data)
	end
end

#digitalRead - check if supplied input is an input pin, if so, read the value and return a 1 or 0. If not input, return -1.
function digitalRead(x::Int)
	if(x > 0 && x <= num_pins)
		if(mcu_pins[x].type == input)
			return mcu_pins[x].state
		else
			return -1
		end
	end
end

#when reading inputs into your new state, only copy over the ones that are initialized as inputs. 
function readOutsideWorld(pins::Int64) #this function loads inputs from the "outside world" for the mcu to process
	#go through all mcu pins
	index = 0
	for pn in mcu_pins
		if(pn.type == input) #if the pin is initialized as an input 
			if(pins&(1<<index)!=0) #get the specific bit out... if it's a 1, 
				pn.state = 1
			else
				pn.state = 0
			end
			#basically if the bit mask is not 0, set the pin to 1, otherwise set it to 0
		end
		index+=1
	end
end
function readOutsideWorld(pins::UInt8)#necessary for julia to accept the inputs properly
	readOutsideWorld(convert(Int64,pins))
end	
function readOutsideWorld(pins::UInt16)
	readOutsideWorld(convert(Int64,pins))
end	
		
function registerPin(index::Int, direction, value)
	if(index <= num_pins && index > 0) #as long as it's a valid index...
		if(direction == 1)#direction 1 is output
			mcu_pins[index] = pin(output, value) #set as an output pin with the value supplied
		else #direction 0 is input
			mcu_pins[index] = pin(input, 0) #set as an input pin, value isn't used and it's initialized to 0 because it gets loaded from the outside
		end
	else
		println("Invalid pin!")
	end
end


#-------------------------END SYSTEM SETUP-------------------------
#-------------------------BEGIN USER CODE -------------------------

##USER CODE GOES HERE TO BE ABLE TO ACCESS INSIDE THE MAIN LOOP
#USER GLOBAL VARS AND SUCH

#digital in handler- stores a memory location/array index for the "pin", the pin's previous state, and the action to perform when triggered (callback)
mutable struct digitalInput #needs to store which pin it is, the past value, and the callback function
	pin_index::Int
	rising_callback::Function
	falling_callback::Function
	prev_state::UInt8 #julia does not allow for default value assignments :(
end
function checkInput(d::digitalInput)
	st = digitalRead(d.pin_index)
	if(st != d.prev_state)#get current state, compare to previous state
		#if different... 
		if(d.prev_state == 1)		#if the previous state is high, the current state must be low so this is the falling edge
			d.prev_state = 0 #update the previous state!
			d.falling_callback() #run the falling callback function
		else #if the previous state is low, the current state must be high so this is the rising edge
			d.prev_state = 1
			d.rising_callback()
		end
	end
end


function printLED_States() #this is because we don't have a physical microcontroller to light up the LEDs, so we have to make do with console printing
	for i = 2:4
		if(mcu_pins[i].state == 1)
			println("LED $(i-1) is lit")
		else
			println("LED $(i-1) is not lit")
		end
	end
	println("---------") #blank line for spacing
end

#note how similar this looks to an arduino program! Wow!
counter = 0
function incrementCounter()
	global counter = (counter + 1) % 8 #3 bit output counter
	digitalWrite(2, counter&1) #"LED" 1, pin 2 is tied to the first bit of the counter
	digitalWrite(3, (counter&2)>>1) #"LED" 2, pin 3 is tied to the 2nd bit of the counter //ohhh
	digitalWrite(4, (counter&4)>>2) #"LED" 3, pin 4 is tied to the 3rd bit of the counter
	printLED_States()
end

function nop()
end

function b2Press()
	println("Button 2 pressed!")
end

#SETUP, SIMILAR TO THE setup() IN ARDUINO
#do your "pin" initializations here, along with registering your input handling
registerPin(1,0,0) #init pin 1 as an input with initial val of 0
registerPin(2,1,0) #init pin 2 as an output with initial val of 0
registerPin(3,1,0) #init pin 3 as an output with initial val of 0 
registerPin(4,1,0) #init pin 4 as an output with initial val of 0
registerPin(5,0,0) #pin 5 is another input!
button1 = digitalInput(1,incrementCounter,nop,0) #button 1 is on pin 1, increment counter on rising edge, do nothing on falling edge, prev_state init to 0
button2 = digitalInput(5,b2Press,nop,0) #a test to make sure inputs that were spread out would work as well, also a demonstration in how easy it is to add new functionality

#a "running" mode, 1 - where the input to the console is treated as the gpio pins so you can interact with the system directly
#a "stimuli" mode, 0 - where a series of inputs is loaded in and interpreted.

mode = 1
if(mode == 0) #stimuli mode
	#MAIN LOOP, IN "RUN THESE STIMULI MODE", not worried about this right now.
	#until no more instructions left
	stimuli = [1,0,0,0,0,1,0,0,1,0] # press the button 3 times, LEDs should end with 1 and 2 on.
	for inputs in stimuli
		readOutsideWorld(inputs) #read the inputs into the mcu
		checkInput(button1) #process the inputs
		checkInput(button2)
	end
elseif(mode == 1) #realtime mode
	#now for runtime mode where you can interact with the system pins in realtime!
	canceled = false
	while(!canceled)
		println("Enter pin values: ") #having trouble with string
		user_input = readline()
		if(user_input=="exit")
			global canceled = true #cancel and don't loop around again
		else #not exit
			try #check for valid input
					#if valid input... 
				numeric_input = Meta.parse(user_input) #get the numeric value, if it exists...
				#STUFF TO RUN ON YOUR INPUT
				readOutsideWorld(numeric_input)
				checkInput(button1)
				checkInput(button2)
			catch
				println("Invalid input!")
			end
		end	
	end
else
	println("Invalid mode!")
end