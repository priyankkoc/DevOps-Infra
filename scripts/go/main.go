package main

import (
	"bufio"
	"fmt"
	"os"
)

func main() {
	var desiredReplicas int32 = 3
	var healthyReplicas int32 = 3
	file, err := os.Open("service.txt")
	if err != nil {
		fmt.Println("Error opening file:", err)
	}
	var services []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		services = append(services, scanner.Text())
	}
	for _, service := range services {
		healthCheckStatus := status_check(service, desiredReplicas, healthyReplicas)
		fmt.Printf("ServiceName: %s Status: %t\n", service, healthCheckStatus)
	}

}
func status_check(services string, desiredReplicas int32, healthyReplicas int32) bool {
	switch desiredReplicas == healthyReplicas {
	case true:
		return true
	case false:
		return false
	}
	return false
}
