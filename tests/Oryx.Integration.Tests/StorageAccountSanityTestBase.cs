﻿// --------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
// --------------------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using System.Xml.XPath;
using Microsoft.Oryx.BuildScriptGenerator.Common;
using Microsoft.Oryx.Integration.Tests;
using Microsoft.Oryx.Tests.Common;
using Xunit;
using Xunit.Abstractions;

namespace Oryx.Integration.Tests
{
    public abstract class StorageAccountSanityTestBase
        : PlatformEndToEndTestsBase, IClassFixture<RepoRootDirTestFixture>
    {
        private readonly string _storageUrl;
        private readonly string _repoRootDir;

        public StorageAccountSanityTestBase(
            string storageUrl,
            ITestOutputHelper output,
            TestTempDirTestFixture testTempDirTestFixture,
            RepoRootDirTestFixture repoRootDirTestFixture)
            : base(output, testTempDirTestFixture)
        {
            _storageUrl = storageUrl;
            _repoRootDir = repoRootDirTestFixture.RepoRootDirPath;
        }

        [Fact]
        public void DotNetCoreContainer_HasExpectedListOfBlobs()
        {
            // Arrange & Act
            var platformName = "dotnet";
            var actualVersions = GetVersionsFromContainer(platformName, "version");
            var expectedVersions = GetListOfVersionsToBuild(platformName);

            // Assert
            foreach (var expectedVersion in expectedVersions)
            {
                Assert.Contains(expectedVersion, actualVersions);
            }
        }

        [Fact]
        public void DotNetCoreContainer_HasExpectedDefaultVersion()
        {
            // Arrange & Act
            var platformName = "dotnet";
            var actualVersion = GetDefaultVersionFromContainer(platformName);
            var expectedVersion = GetDefaultVersion(platformName);

            // Assert
            Assert.Equal(expectedVersion, actualVersion);
        }

        [Fact]
        public void PythonContainer_HasExpectedListOfBlobs()
        {
            // Arrange & Act
            var platformName = "python";
            var actualVersions = GetVersionsFromContainer(platformName, "version");
            var expectedVersions = GetListOfVersionsToBuild(platformName);

            // Assert
            foreach (var expectedVersion in expectedVersions)
            {
                Assert.Contains(expectedVersion, actualVersions);
            }
        }

        [Fact]
        public void PythonContainer_HasExpectedDefaultVersion()
        {
            // Arrange & Act
            var platformName = "python";
            var actualVersion = GetDefaultVersionFromContainer(platformName);
            var expectedVersion = GetDefaultVersion(platformName);

            // Assert
            Assert.Equal(expectedVersion, actualVersion);
        }

        [Fact]
        public void NodeJSContainer_HasExpectedListOfBlobs()
        {
            // Arrange & Act
            var platformName = "nodejs";
            var actualVersions = GetVersionsFromContainer(platformName, "version");
            var expectedVersions = GetListOfVersionsToBuild(platformName);

            // Assert
            foreach (var expectedVersion in expectedVersions)
            {
                Assert.Contains(expectedVersion, actualVersions);
            }
        }

        [Fact]
        public void NodeJSContainer_HasExpectedDefaultVersion()
        {
            // Arrange & Act
            var platformName = "nodejs";
            var actualVersion = GetDefaultVersionFromContainer(platformName);
            var expectedVersion = GetDefaultVersion(platformName);

            // Assert
            Assert.Equal(expectedVersion, actualVersion);
        }

        private XDocument GetMetadata(string platformName)
        {
            var url = string.Format(SdkStorageConstants.ContainerMetadataUrlFormat, _storageUrl, platformName);
            var blobList = _httpClient.GetStringAsync(url).Result;
            return XDocument.Parse(blobList);
        }

        private List<string> GetVersionsFromContainer(string platformName, string metadataElementName)
        {
            var xdoc = GetMetadata(platformName);
            var supportedVersions = new List<string>();
            foreach (var metadataElement in xdoc.XPathSelectElements($"//Blobs/Blob/Metadata"))
            {
                var childElements = metadataElement.Elements();
                var versionElement = childElements.Where(e => string.Equals(
                        metadataElementName,
                        e.Name.LocalName,
                        StringComparison.OrdinalIgnoreCase))
                    .FirstOrDefault();
                if (versionElement != null)
                {
                    supportedVersions.Add(versionElement.Value);
                }
            }
            return supportedVersions;
        }

        private string GetDefaultVersionFromContainer(string platformName)
        {
            var defaultVersionContent = _httpClient
                .GetStringAsync($"{_storageUrl}/{platformName}/{SdkStorageConstants.DefaultVersionFileName}")
                .Result;

            string defaultVersion = null;
            using (var stringReader = new StringReader(defaultVersionContent))
            {
                string line;
                while ((line = stringReader.ReadLine()) != null)
                {
                    // Ignore any comments in the file
                    if (!line.StartsWith("#") || !line.StartsWith("//"))
                    {
                        defaultVersion = line.Trim();
                        break;
                    }
                }
            }
            return defaultVersion;
        }

        private List<string> GetListOfVersionsToBuild(string platformName)
        {
            var versionFile = Path.Combine(
                _repoRootDir,
                "platforms",
                platformName,
                SdkStorageConstants.VersionsToBuildFileName);
            if (!File.Exists(versionFile))
            {
                throw new InvalidOperationException($"Could not find file '{versionFile}'");
            }

            var versions = new List<string>();
            using (var streamReader = new StreamReader(versionFile))
            {
                string line = null;
                while ((line = streamReader.ReadLine()) != null && !string.IsNullOrEmpty(line))
                {
                    // ignore comments
                    if (line.StartsWith("#"))
                    {
                        continue;
                    }
                    var parts = line.Split(",");
                    versions.Add(parts[0].Trim());
                }
            }

            return versions;
        }

        private string GetDefaultVersion(string platformName)
        {
            var file = Path.Combine(
                _repoRootDir,
                "platforms",
                platformName,
                SdkStorageConstants.DefaultVersionFileName);
            if (!File.Exists(file))
            {
                throw new InvalidOperationException($"Could not file default version file '{file}'.");
            }

            string defaultVersion = null;
            using (var streamReader = new StreamReader(file))
            {
                string line = null;
                while ((line = streamReader.ReadLine()) != null && !string.IsNullOrEmpty(line))
                {
                    // ignore comments
                    if (line.StartsWith("#"))
                    {
                        continue;
                    }

                    defaultVersion = line.Trim();
                }
            }

            if (string.IsNullOrEmpty(defaultVersion))
            {
                throw new InvalidOperationException("Default version cannot be empty");
            }

            return defaultVersion;
        }
    }
}
