package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	yaml "github.com/ghodss/yaml"
	machinev1 "github.com/metal3-io/baremetal-operator/pkg/apis/metal3/v1alpha1"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var (
	BareMetalHosts map[string]*machinev1.BareMetalHost
	InstallConfig  map[string]interface{}
	Secrets        map[string]*v1.Secret
)

func init() {
	Secrets = map[string]*v1.Secret{}
	BareMetalHosts = map[string]*machinev1.BareMetalHost{}
}

func main() {
	var directory os.FileInfo
	var err error

	argsWithoutProg := os.Args[1:]

	yamlFilesPath := argsWithoutProg[0]

	if directory, err = os.Stat(yamlFilesPath); os.IsNotExist(err) {
		fmt.Printf("Error: path '%s' does not exist!\n", yamlFilesPath)
		os.Exit(1)
	}

	if !directory.IsDir() {
		fmt.Printf("Error: path '%s' is not a directory!\n", yamlFilesPath)
		os.Exit(1)
	}

	err = filepath.Walk(yamlFilesPath, func(path string, info os.FileInfo, err error) error {
		if !info.IsDir() {
			bytes, err := ioutil.ReadFile(path)

			if err != nil {
				return err
			}

			if info.Name() == "install-config.yaml" {
				// HACK needed because install-config.yaml does not have Kind
				// TODO: What fields do we care about in install-config.yaml?
				fmt.Println("Found 'install-config.yaml'")

				err = yaml.Unmarshal(bytes, &InstallConfig)

				if err != nil {
					return err
				}
			} else {
				var base metav1.TypeMeta

				err = yaml.Unmarshal(bytes, &base)

				if err != nil {
					return err
				}

				fmt.Printf("Found '%s' in %s\n", base.Kind, info.Name())

				// Lots TODO here
				switch base.Kind {
				case "BareMetalHost":
					var bareMetalHost machinev1.BareMetalHost

					err = yaml.Unmarshal(bytes, &bareMetalHost)

					if err != nil {
						return err
					}

					BareMetalHosts[bareMetalHost.ObjectMeta.Name] = &bareMetalHost

				case "Secret":
					var secret v1.Secret
					err = yaml.Unmarshal(bytes, &secret)

					if err != nil {
						return err
					}

					Secrets[secret.ObjectMeta.Name] = &secret

				default:
					fmt.Printf("Warning: Unknown Kind '%s' encountered.  Skipping.\n", base.Kind)
				}
			}
		}

		return nil
	})

	if err != nil {
		fmt.Println("Error:", err)
	}

	if err := verify(); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}

	fmt.Println("Verification passed.")

	// TODO: ?????
	// if err := writePrepBmHostSrc(); err != nil {
	// 	fmt.Println("Error:", err)
	// 	os.Exit(1)
	// }

}

func verify() error {

	bootstrapCount := 0
	masterCount := 0

	// Secrets need username and password
	for name, obj := range Secrets {
		if obj.StringData["username"] == "" || obj.StringData["password"] == "" {
			return fmt.Errorf("Secret '%s' requires username and password StringData", name)
		}
	}

	// All BareMetalHosts must have a credential secret
	for name, obj := range BareMetalHosts {
		switch obj.Spec.HardwareProfile {
		case "bootstrap":
			bootstrapCount++
		case "master":
			masterCount++
		}

		if Secrets[obj.Spec.BMC.CredentialsName] == nil {
			return fmt.Errorf("No Secret named '%s' found for %s", obj.Spec.BMC.CredentialsName, name)
		}
	}

	// Need 1 bootstrap
	if bootstrapCount != 1 {
		return fmt.Errorf("One and only one bootstrap node required")
	}

	// Need 1-3 master(s)
	if masterCount < 1 || masterCount > 3 {
		return fmt.Errorf("1 to 3 master nodes required")
	}

	// Install config needs pull secret
	if pullSecret, ok := InstallConfig["pullSecret"].(string); !ok || pullSecret == "" {
		return fmt.Errorf("Install config requires a pull secret")
	}

	// Install config needs public ssh key
	if sshKey, ok := InstallConfig["sshKey"].(string); !ok || sshKey == "" {
		return fmt.Errorf("Install config requires an SSH key")
	}

	return nil
}

func writePrepBmHostSrc() error {
	// TODO: Writing to working directory for now
	filename, _ := filepath.Abs("./prep_bm_host.src")

	// Construct file contents
	contents := fmt.Sprintf("# This file stores environment variables required by the prep_bm_host.sh script.\n" +
		"# Set the values here and then run prep_bm_host.sh.\n\n" +
		"export PROV_INTF=\n" +
		"export BM_INTF=\n" +
		"export EXT_INTF=\n" +
		"export BSTRAP_BM_MAC=\n" +
		"export MASTER_BM_MAC=\n" +
		"export WORKER_BM_MAC=\n")

	// Get bytes and write to file
	err := ioutil.WriteFile(filename, []byte(contents), 0644)

	if err != nil {
		return err
	}

	return err
}
