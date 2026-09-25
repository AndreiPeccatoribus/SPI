# SPI Interface Implementation

## Overview
This project implements an SPI master/slave interface based on a looped shift register architecture. It supports full-duplex communication, multiple slave selection (with different quartz), and synchronization for reliable data exchange.
At first I made a very simple but unrelieble schem but later manged to get closer to OpenTitan features.
## Features
- List key features:  
  - 16-bit shift register (or whatever your width is, 16-,it is enough to represent float numbers preciesly)  
  - Master and slave modes  
  - Multiple slave select lines (implementation via numbers)
  - Built-in synchronizer for clock domain crossing  
  - Configurable clock prescaler  
  - [Add more]

## Architecture / Design


## Interface


## Usage



## Code Description


## Testing
<img width="1036" height="506" alt="изображение" src="https://github.com/user-attachments/assets/2d13d66b-1fa6-4e42-b0c4-7900e09aeffd" />

## License
“For academic use only”.

## Author
Andrei Vladimirovich Bodeev, 25.09.2026, krjekovichav@gmail.com.
